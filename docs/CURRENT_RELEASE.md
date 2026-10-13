# Current production release — ChatGPT Web iOS 0.7.2 Build 4

- **Official install**: https://ipa.78175132.xyz/
- **IPA ID**: `12112229-485f-49e1-afba-896caa875853`
- **Signed source**: `8440857cf0bf485ce79d408b74b8380069eb08dc`
- **Signing CI**: https://github.com/masakacj/chatgpt-web/actions/runs/38327609864 (success).
- **Bundle ID**: `com.masakacj.chatgptweb`.
- **Live PC backend**: independent PC Bridge 0.3.10, secure HTTPS `https://chatgpt-pc.781751.xyz:58443`.
- **Unverified**: real-device full end-to-end, long-dialog performance P95 and physical-phone overwrite/Keychain persistence.

The cleaned source keeps the exact signed source files for `App/`, `Resources/`, `SafariScriptAction/`, and `safari/chatgpt-safari.user.js`; the version/CI/README were modernized to reflect the current 0.7.2 release. The embedded userscript's own version remains 0.6.0 because that is what was shipped. The current telemetry worker is kept because the iOS app still calls its opt-in endpoint.

The prior **0.6.0 Build 221** remains in the separate IPA signing service's backup for rollback; it is not the current source here. GitHub actions on `main` are source/build checks only, not deploy/sign actions. The independently hosted PC Bridge source and confidential pairing credentials do not belong in this repo.

Repository cleanup removed deprecated in-repository experiments, one-off migration scripts, old CI and Handoff files. No working native iOS source file was rewritten by the cleanup.
