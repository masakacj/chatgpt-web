# Optimizer OfficeServer GOST — 2026-11-17 deployment handoff

## Target architecture (now verified)
```
iPhone Optimizer (v2) -- HTTPS CONNECT/TLS --> gostos.781751.xyz:18445
  AliDNS: gostos CNAME 781751.xyz (Home public IP follows existing DDNS)
  Home iKuai: WAN TCP 18445 -> 192.168.233.127:18445 (DNAT id 25)
  Home Portainer: existing gost-relay-server relay TCP 20443
  OfficeServer outbound RTCP -> Home 20443; binds Home TCP :18445
  OfficeServer local TLS gateway :18445 -> 127.0.0.1:18545
  OfficeServer GOST HTTP CONNECT: Basic authentication required

Office backup:
  iPhone Optimizer -- TLS CONNECT --> gosto.781751.xyz:18444
  Home iKuai: WAN TCP 18444 -> 192.168.233.127:18444 (DNAT id 26)
  Existing Home Portainer Office GOST frontend -> Office 10.0.92.89:18544
```
**Do not add a second Home relay container.** Both Office and OfficeServer coexist with the existing Relay, using different public listener ports.

## Deployment evidence
- iKuai DNAT before: 9 rules; after: 11 rules; existing 20443/38388 mappings were not changed.
- New OfficeServer RTCP: `gost-optimizer-rtcp.service` enabled/running, remote bind `18445/tcp OK`.
- OfficeServer local services: `gost-optimizer-tls-gateway.service` and `gost-optimizer-connect.service` enabled/running.
- Home LAN `192.168.233.127:18445`: TCP and TLS handshake trusted.
- Home public `59.61.100.121:18445`: TLS handshake trusted and cert SAN matches `gostos.781751.xyz`.
- No proxy credentials -> HTTP 407; correct GOST credential -> CONNECT HTTP 200.
- Full external proxy request to `https://example.com/`: CONNECT=200, HTTPS=200, both TLS verifications successful.
- Office fallback `gosto.781751.xyz:18444`: full HTTPS proxy verification passed via existing private GOST verifier.
- AliDNS `gostos` changed from OfficeServer's former public A record to `CNAME 781751.xyz`, TTL 600.
- OfficeServer TLS certificate Let's Encrypt valid until **2027-02-15**; private key remains on OfficeServer mode 0600.

## Client work
Branch: `feature/optimizer-officeserver-gost-20261117`
- `OptimizerProxyMode`: `officeServer`, `office`, explicit `direct`. New plan v2 has **no Home routing**.
- OfficeServer endpoint `gostos.781751.xyz:18445` (username `optimizer-os`); backup Office endpoint migrated from v1.
- OfficeServer credentials are independent; never reuse the old Home password.
- Existing v1 data and Office Keychain credentials remain for rollback; no automatic direct fallback.
- New client configuration recovery uses separate app scope `optimizer-v2`, leaving existing `optimizer` config untouched.
- **Do not sign/publish/promote until v2 credentials are stored in the private config service and native CI passes.** An unconfigured new client deliberately fails closed.

## Outstanding work
1. Provision only app ID `optimizer-v2` in existing private config service via its approved `admin.mjs set optimizer-v2` workflow. Secret should be loaded directly from OfficeServer's root-owned GOST file (via protected staging) and current private Office backup. Do not write passwords to GitHub, IPA, shell history or logs. Do not alter the existing `optimizer` app record.
2. Verify config recovery JSON schema and both proxy endpoints from a fresh client installation.
3. Validate iOS CI, merge/rebase into the authorized signed-candidate lane, bump Optimizer version/build, sign candidate, run physical iPhone QA and then promote.
4. Schedule certificate renewal before 2027-02-15; the CSR-mode Certbot issuance does not auto-renew.

## Scoped rollback
- OfficeServer new RTCP only:
  `node /home/devspace/gost-standby/optimizer-rtcp-deploy.mjs rollback`.
  Original Office Relay and GOST unchanged.
- iKuai new DNAT only:
  `python3 /home/devspace/ikuai-optimizer-18445-scoped.py rollback` and
  `python3 /home/devspace/ikuai-optimizer-18444-scoped.py rollback`;
  each requires matching its exact owned rule before deletion.
- DNS `gostos` previously A `59.60.0.178`; only revert if needed and explicitly approved.
- OfficeServer local TLS/GOST services can be separately disabled after stopping its RTCP.
- Previously installed Optimizer and `optimizer` v1 config are untouched.
