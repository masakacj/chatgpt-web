#!/usr/bin/env python3
"""R78: artifact-based, idempotent candidate signing; network retries only."""
import json
import os
import pathlib
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

BASE = "https://ipa.781751.xyz:58443"
DIST = pathlib.Path("dist")
IPA = DIST / "candidate-unsigned.ipa"
RUN = os.environ.get("GITHUB_RUN_ID", "")
SHA = os.environ.get("GITHUB_SHA", "")
REPO = os.environ.get("GITHUB_REPOSITORY", "")
TOKEN = os.environ.get("GH_RUN_TOKEN", "")
VERSION = "0.7.12"
BUILD = "14"
BUNDLE = "com.masakacj.chatgptweb"
STATUS_PATH = "/api/v1/sign/candidate/status"
DELAYS = (10, 30)
class SignFailure(Exception):
    def __init__(self, category, detail):
        self.category, self.detail = category, detail
        super().__init__(f"{category}: {detail}")

def request(url, *, data=None, headers=None, timeout=25):
    method = "POST" if data is not None else "GET"
    req = urllib.request.Request(url, data=data, method=method, headers=headers or {})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.status, resp.read(32768).decode("utf-8", errors="replace")
    except urllib.error.HTTPError as e:
        return e.code, e.read(32768).decode("utf-8", errors="replace")
    except (urllib.error.URLError, TimeoutError, ConnectionError, OSError) as e:
        return 0, type(e).__name__

def decode(raw):
    try:
        doc = json.loads(raw)
        return doc if isinstance(doc, dict) else {}
    except (ValueError, TypeError):
        return {}

def classify(code, body):
    message = str(decode(body).get("error", "")).lower()
    if (code in (401, 403, 404, 422) or
        any(word in message for word in ("github run verification", "untrusted", "credentials expired",
                                         "missing github bearer", "profile", "bundle id mismatch"))):
        return "SIGNING_AUTH_OR_POLICY"
    if code in (400, 413, 415):
        return "SIGNING_BAD_ARTIFACT"
    if code in (0, 408, 429, 500, 502, 503, 504):
        return "SIGNING_TRANSIENT_INFRA"
    if code == 409 and "in_progress" in str(decode(body).get("status", "")).lower():
        return "SIGNING_IN_PROGRESS"
    return "SIGNING_UNEXPECTED_RESPONSE"

def lookup():
    query = urllib.parse.urlencode({"app_key": "chatgpt-web", "run_id": RUN, "sha": SHA})
    code, raw = request(BASE + STATUS_PATH + "?" + query, timeout=25)
    doc = decode(raw)
    if code == 200 and doc.get("status") == "SIGNED":
        return "signed", doc
    if code == 202 and doc.get("status") == "SIGNING":
        return "pending", doc
    if code == 404 and doc.get("status") == "NOT_FOUND":
        return "missing", doc
    if code == 409 and doc.get("status") == "SIGNED_ARTIFACT_MISSING":
        raise SignFailure("SIGNING_ARTIFACT_MISSING", "previous signing record is incomplete")
    # Unknown lookup is not permission to perform a potentially duplicate POST.
    raise SignFailure("SIGNING_STATUS_UNAVAILABLE", f"status HTTP {code}; refusing duplicate upload")

def validate_result(doc):
    if (not doc.get("ok") or doc.get("channel") != "candidate" or doc.get("promoted") is not False
        or doc.get("source_sha") != SHA or str(doc.get("run_id")) != RUN
        or doc.get("version") != VERSION or str(doc.get("build")) != BUILD
        or doc.get("bundle_id") != BUNDLE
        or not str(doc.get("ipa_url", "")).startswith(BASE + "/ipa/")
        or not str(doc.get("manifest_url", "")).startswith(BASE + "/manifest/")):
        raise SignFailure("SIGNING_RESULT_IDENTITY", "signed Run/SHA/version/bundle mismatch")
    return doc

def summary(text):
    out = os.environ.get("GITHUB_STEP_SUMMARY", "")
    if out:
        with open(out, "a", encoding="utf-8") as f:
            f.write(text + "\n")

def main():
    if (REPO != "masakacj/chatgpt-web" or len(SHA) != 40 or
        not all(c in "0123456789abcdef" for c in SHA.lower()) or not RUN.isdecimal()
        or not TOKEN or not IPA.is_file() or IPA.stat().st_size < 10000
        or IPA.stat().st_size > 64 * 1024 * 1024):
        raise SignFailure("SIGNING_BAD_INPUT", "repo, run, SHA, token, or IPA artifact invalid")
    DIST.mkdir(exist_ok=True)
    before_code, before_raw = request(BASE + "/api/v1/apps/chatgpt-web/latest")
    if before_code != 200:
        raise SignFailure("SIGNING_STABLE_LOOKUP", f"stable before HTTP {before_code}")
    before = decode(before_raw)
    if before.get("app_key") != "chatgpt-web":
        raise SignFailure("SIGNING_STABLE_LOOKUP", "unexpected stable app")
    (DIST / "stable-before.json").write_text(json.dumps(before), encoding="utf-8")
    ipa_bytes = None
    signed = None
    for attempt in range(3):
        state, doc = lookup()
        if state == "signed":
            signed = validate_result(doc)
            break
        if state == "missing":
            if ipa_bytes is None:
                ipa_bytes = IPA.read_bytes()
            headers = {
                "Authorization": "Bearer " + TOKEN,
                "X-GitHub-Repository": REPO,
                "X-GitHub-Run-Id": RUN,
                "X-GitHub-Sha": SHA,
                "X-App-Key": "chatgpt-web",
                "Content-Type": "application/octet-stream",
            }
            code, raw = request(BASE + "/api/v1/sign?channel=candidate",
                                data=ipa_bytes, headers=headers, timeout=240)
            if code in (200, 201):
                # A successful POST is still reconciled with the authoritative index.
                state, doc = lookup()
                if state == "signed":
                    signed = validate_result(doc)
                    break
            else:
                category = classify(code, raw)
                if category not in ("SIGNING_TRANSIENT_INFRA", "SIGNING_IN_PROGRESS"):
                    raise SignFailure(category, f"sign request returned HTTP {code}")
                # A failed response is not evidence the signer did not finish.
                state, doc = lookup()
                if state == "signed":
                    signed = validate_result(doc)
                    break
        if attempt < len(DELAYS):
            summary(f"R78 signing: transient/pending; checking same Run/SHA after {DELAYS[attempt]} s")
            time.sleep(DELAYS[attempt])
    if signed is None:
        raise SignFailure("SIGNING_RETRIES_EXHAUSTED", "3 attempts max; no verified signed candidate")
    after_code, after_raw = request(BASE + "/api/v1/apps/chatgpt-web/latest")
    if after_code != 200:
        raise SignFailure("SIGNING_STABLE_LOOKUP", f"stable after HTTP {after_code}")
    after = decode(after_raw)
    (DIST / "stable-after.json").write_text(json.dumps(after), encoding="utf-8")
    if before != after:
        raise SignFailure("SIGNING_STABLE_CHANGED", "stable pointer changed during candidate operation")
    (DIST / "candidate-sign-result.json").write_text(
        json.dumps(signed, indent=2), encoding="utf-8")
    print(json.dumps({"status": "CANDIDATE_SIGNED_VERIFIED", "runId": RUN,
                      "sourceSha": SHA, "candidateId": signed.get("id"),
                      "reused": signed.get("reused", False),
                      "stableUnchanged": True}))
    summary("### R78 candidate signing: VERIFIED\n" +
            f"- Source Run/SHA: {RUN} / {SHA}\n" +
            f"- Signed IPA candidate ID: {signed.get('id')}\n- Stable pointer unchanged")

if __name__ == "__main__":
    try:
        main()
    except SignFailure as e:
        DIST.mkdir(exist_ok=True)
        (DIST / "sign-failure.json").write_text(json.dumps({
            "category": e.category, "detail": e.detail,
            "runId": RUN, "sourceSha": SHA}, indent=2), encoding="utf-8")
        print(f"::error title=R78 {e.category}::{e.detail}", file=sys.stderr)
        summary(f"### R78 signing failure\n- Category: {e.category}\n- {e.detail}")
        sys.exit(1)
