# Mirror Cleanup Handoff — planned 0.7.3 Build 5

Date: 2026-10-13
Status: blocked until ChatGPT Web Optimized F5 physical-device acceptance passes

## Purpose

After the independent Web Optimized app is accepted, remove the Web/Safari and release-unreachable legacy Companion routes from the existing structured-mirror binary without changing mirror behavior or user data.

## Preconditions

- Web Optimized signed candidate installed and fully accepted on a physical iPhone;
- independent Web Optimized rollback artifact exists;
- mirror 0.7.2 Build4 signed IPA and stable-index backup are verified;
- current SharedTab result bundle and physical regression baseline exist;
- no unresolved pairing, draft or receipt migration issue.

## Required extraction before deletion

Move mirror-used DTOs and policies out of legacy-named files while preserving Codable field names and behavior:

- `PCRemoteBlock`
- `PCRemoteLink`
- `PCRemoteMessage`
- `PCInteractionButton`
- `PCInteractionCard`
- required history/pending records
- endpoint validation and hashing

Replace the old `PCRemoteTab` migration dependency with a private `STLegacyTab` that reads only `tabId`. Keep the existing JSON legacy draft import initially, add a one-time migration marker, and do not delete old files until one stable mirror release has confirmed migration.

## Planned removals

- `ChatGPTWebView.swift`
- `UnifiedScriptStore.swift`
- `ConversationResilienceStore.swift`
- `ConversationResilienceBridge.swift`
- `NativePerformanceProbe.swift`
- `Resources/NativeConversationBootstrap.js`
- `Resources/NativeConversationClient.js`
- bundled userscript and hot-update path
- `SafariContainerView.swift`
- `ChatGPTScriptAction` target/dependency/source
- release-unreachable `PCCompanionRootView.swift`
- `PCCompanionView.swift`
- `NativeConversationScreen.swift`
- `PCSidebarView.swift`
- `PCCompanionTestProtocol.swift`
- old companion UI tests and launch flags

The mirror root becomes `SharedTabScreen` directly. Remove `PCCompanion.selected` and the “原网页模式” controls. Restrict the test-Bridge selector to DEBUG/internal builds if it is still needed operationally.

## Must remain unchanged

- mirror bundle ID and Keychain service;
- SharedPC client ID;
- SharedPCCompanion state;
- all drafts and pending/unknown receipts;
- SharedTab protocol and accessibility contracts;
- formal Bridge endpoint and pairing;
- current native mirror behavior.

## Acceptance

Run all SharedTab policy/UI cases, real formal-Bridge compatibility, upgrade from 0.7.2, background/offline flows, search/new/project actions, draft and unknown-receipt cases, plus physical-device side-by-side testing with Web Optimized.

Promote the cleanup candidate only if mirror data and behavior are unchanged. Rollback restores the preserved signed 0.7.2 Build4 IPA and its stable index; cleanup must not write a schema unreadable by 0.7.2.
