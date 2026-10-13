# Web Optimized 0.1.0 Candidate Signing Handoff

Date: 2026-10-13
Status: macOS compile and Simulator tests passed; online signer deployment required; no candidate or stable release exists
Audience: Agent with `mcpdebian` DevSpace access (`ws_3a9515d2c0`)

## Immutable identities

### iOS source

- Repository: `masakacj/chatgpt-web`
- Branch: `feature/web-optimized-010-20261013`
- Exact tested source: `7e855d6aa5466c14b9dac21b38b117ca643686a1`
- Product: ChatGPT Web Optimized
- Bundle ID: `com.masakacj.chatgptweb.optimized`
- Version/build: `0.1.0 (1)`
- Candidate workflow: `.github/workflows/web-optimized-candidate.yml`

### Signer source

- Repository: private `masakacj/laocai-manager`
- Branch: `feature/web-optimized-signer-20261013`
- Exact tested signer source: `13d56ac`
- Baseline/deployed-snapshot parent: `c5b9b7b652a944925659cdd674137fc941071c15`
- Source workspace on mcpdebian: `/home/devspace/ipa-signer`
- Live runtime: `/opt/ipa-signer`
- DevSpace workspace: `ws_3a9515d2c0`

Do not deploy private-repository `main`; it does not contain the isolated deployed candidate-channel snapshot. Transfer only the four tested files named below from `13d56ac` onto the existing `/home/devspace/ipa-signer` source workspace.

## Verified iOS evidence

### Full source/build run

- Run: `38351064043`
- Conclusion: success
- Passed: mirror and optimized source checks, existing mirror policies, XcodeGen, mirror SharedTab Simulator regression, Web Optimized unit/UI tests, mirror Release compile, and Web Optimized Release compile.

### Candidate run before signer deployment

- Run: `38351063992`
- Source: `7e855d6aa5466c14b9dac21b38b117ca643686a1`
- Passed: every source/contract check, optimized Simulator tests, unsigned Release compile, and unsigned IPA packaging.
- Failed only at: `Sign into independent candidate channel only`.
- Unsigned evidence artifact ID: `11791485764` (`web-optimized-candidate-7e855d6...`).

The failure is expected from the old live signer allowlist: it accepts only app key `chatgpt-web`, old branch `feature/shared-tab-native-070-20261011`, and old workflow `shared-tab-candidate.yml`.

## Signer changes in `13d56ac`

Transfer exactly:

1. `infra/ipa-signer/candidate-channel.mjs`
2. `infra/ipa-signer/server.mjs`
3. `infra/ipa-signer/scripts/candidate-channel.test.mjs`
4. `infra/ipa-signer/deploy/install-candidate-channel.sh`

Behavior added:

- app key `chatgpt-web-optimized`;
- bundle source/target `com.masakacj.chatgptweb.optimized`;
- exact candidate branch/workflow allowlist;
- existing `chatgpt-web` rules remain unchanged;
- candidate app registration creates no false stable/latest;
- optimized candidate cannot mutate mirror latest/history;
- Apple Profile Manager may create/fetch the new app-specific profile using existing configured Apple credentials;
- deployment backs up both live `server.mjs` and `candidate-channel.mjs`, checks signing idle, restarts service, verifies mirror stable unchanged, and automatically rolls back on error.

Local validation already completed:

- `node --check server.mjs`: pass
- `node --check candidate-channel.mjs`: pass
- `node --test scripts/candidate-channel.test.mjs`: 12/12 pass
- `bash -n deploy/install-candidate-channel.sh`: pass

## mcpdebian execution sequence

### 1. Read-only preflight

- inspect `/home/devspace/ipa-signer` and `/opt/ipa-signer`;
- verify the source files still correspond to the deployed candidate snapshot lineage;
- verify `ipa-signer.service` and `ipa-signer-tunnel.service` are active;
- verify no `zsign` process and no active signing request;
- save current `GET http://127.0.0.1:8791/api/v1/apps/chatgpt-web/latest` exactly;
- do not read or print signing keys, P12 password, Apple private key, admin token, profile bodies, release index contents beyond public metadata, or IPA payloads.

### 2. Transfer only tested source

Copy the four files from private branch commit `13d56ac` to matching locations under `/home/devspace/ipa-signer`. Do not replace the source tree wholesale and do not merge private-repo main.

### 3. Revalidate on mcpdebian

```bash
node --check /home/devspace/ipa-signer/server.mjs
node --check /home/devspace/ipa-signer/candidate-channel.mjs
node --test /home/devspace/ipa-signer/scripts/candidate-channel.test.mjs
bash -n /home/devspace/ipa-signer/deploy/install-candidate-channel.sh
```

Expected: 12/12 tests.

### 4. Deploy

```bash
bash /home/devspace/ipa-signer/deploy/install-candidate-channel.sh
```

The script must report mirror stable unchanged and print backup paths. If it fails, preserve its automatic rollback output and stop; do not hand-copy files into `/opt` afterward.

### 5. Verify deployment

- `systemctl is-active ipa-signer.service` → active
- local health → success
- public `https://ipa.78175132.xyz/api/v1/apps/chatgpt-web/latest` remains 0.7.2 Build4 and byte-equivalent to preflight
- `GET /api/v1/apps/chatgpt-web-optimized/candidate` may remain 404 before first successful sign
- no change to any existing app latest/history/profile/index record

## Retrigger candidate after deployment

Use authenticated GitHub CLI/API from a trusted environment:

```bash
gh workflow run web-optimized-candidate.yml \
  --repo masakacj/chatgpt-web \
  --ref feature/web-optimized-010-20261013
```

Do not retry the original signing POST directly. Start a new workflow run only after the prior run is conclusively failed and signer deployment is verified.

Expected candidate workflow behavior:

1. rerun source/contract checks;
2. rerun Simulator tests;
3. rebuild unsigned 0.1.0 Build1;
4. POST once to candidate signing endpoint with app key `chatgpt-web-optimized`;
5. signer auto-creates/fetches app-specific profile if Apple credentials permit;
6. mirror stable before/after matches exactly;
7. workflow downloads and verifies manifest/IPA, ZIP CRC, bundle/version/build, embedded profile and `_CodeSignature`;
8. candidate remains unpromoted.

## Post-sign acceptance

Record run ID/source SHA, candidate ID/install page, manifest/IPA URLs, signed IPA bytes/SHA-256, Bundle/version/build, profile UUID/expiry/Team ID/app identifier, mirror stable equality, candidate verification JSON, and `physicalIPhoneAccepted:false`.

Read-only public checks:

- `/api/v1/apps/chatgpt-web-optimized/candidate` → 200;
- candidate install page, manifest and IPA → 200;
- IPA byte count matches workflow evidence;
- existing `/api/v1/apps/chatgpt-web/latest` remains 0.7.2 Build4.

## Promotion boundary

**Do not promote this candidate to stable in this handoff.** Physical-iPhone login, isolation, functional and performance acceptance is required before the first Web Optimized stable release. Candidate install-center publication is the endpoint of this task.

## Rollback

If signer deployment regresses, use backup paths printed by the deployment script, restore both files, restart `ipa-signer.service`, and verify mirror stable remains 0.7.2 Build4. Do not delete profiles, keys, old IPA, candidate records or index history.

If candidate signing fails after a profile or partial temporary file is created, inspect the explicit failure category. Do not repeat the signing POST automatically and do not delete credentials/profile material. A new GitHub workflow run is permitted only after the prior result is conclusively failed and the cause is corrected.

## Current installation-center state before handoff

- `chatgpt-web/latest`: HTTP200, 0.7.2 Build4
- `chatgpt-web-optimized/latest`: HTTP404 `unknown app`
- `chatgpt-web-optimized/candidate`: HTTP404 `no candidate channel`
- No Web Optimized signed IPA has been published.
