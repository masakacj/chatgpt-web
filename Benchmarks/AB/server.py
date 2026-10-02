from __future__ import annotations

import argparse
import json
import pathlib
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

ROOT = pathlib.Path(__file__).resolve().parent
FIXTURE = (ROOT / "fixture.html").read_text(encoding="utf-8")


class State:
    def __init__(self, report_path: pathlib.Path):
        self.report_path = report_path
        self.marks: dict[str, float] = {}
        self.requests: dict[str, float] = {}

    def append(self, payload: dict) -> None:
        run_id = str(payload.get("runId") or "")
        row = {
            "receivedAtMs": round(time.time() * 1000),
            "launchMarkMs": self.marks.get(run_id),
            "requestAtMs": self.requests.get(run_id),
            **payload,
        }

        if row["launchMarkMs"] and row["requestAtMs"]:
            row["launchToRequestMs"] = round(
                row["requestAtMs"] - row["launchMarkMs"],
                2,
            )

        self.report_path.parent.mkdir(parents=True, exist_ok=True)
        with self.report_path.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(row, ensure_ascii=False) + "\n")


def make_handler(state: State):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, fmt: str, *args):
            return

        def _json(self, status: int, payload: dict):
            body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
            self.send_response(status)
            self.send_header("content-type", "application/json; charset=utf-8")
            self.send_header("content-length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            parsed = urlparse(self.path)
            query = parse_qs(parsed.query)

            if parsed.path == "/fixture":
                run_id = (query.get("run") or [""])[0]
                if run_id:
                    state.requests[run_id] = time.time() * 1000

                body = FIXTURE.encode("utf-8")
                self.send_response(200)
                self.send_header("content-type", "text/html; charset=utf-8")
                self.send_header("cache-control", "no-store")
                self.send_header("content-length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
                return

            if parsed.path == "/mark":
                run_id = (query.get("run") or [""])[0]
                if not run_id:
                    self._json(400, {"ok": False, "error": "run required"})
                    return

                state.marks[run_id] = time.time() * 1000
                self._json(200, {"ok": True, "run": run_id})
                return

            if parsed.path == "/status":
                count = 0
                if state.report_path.exists():
                    count = sum(
                        1
                        for line in state.report_path.read_text(
                            encoding="utf-8"
                        ).splitlines()
                        if line.strip()
                    )
                self._json(200, {"ok": True, "reports": count})
                return

            self._json(404, {"ok": False, "error": "not found"})

        def do_POST(self):
            parsed = urlparse(self.path)
            if parsed.path != "/report":
                self._json(404, {"ok": False, "error": "not found"})
                return

            length = int(self.headers.get("content-length") or "0")
            raw = self.rfile.read(length)
            try:
                payload = json.loads(raw.decode("utf-8"))
            except Exception as error:
                self._json(400, {"ok": False, "error": str(error)})
                return

            state.append(payload)
            self._json(200, {"ok": True})

    return Handler


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--report", default="ab-reports.jsonl")
    args = parser.parse_args()

    report_path = pathlib.Path(args.report).resolve()
    if report_path.exists():
        report_path.unlink()

    state = State(report_path)
    server = ThreadingHTTPServer(
        (args.host, args.port),
        make_handler(state),
    )

    print(
        json.dumps(
            {
                "ok": True,
                "url": f"http://{args.host}:{args.port}/fixture",
                "report": str(report_path),
            }
        ),
        flush=True,
    )

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
