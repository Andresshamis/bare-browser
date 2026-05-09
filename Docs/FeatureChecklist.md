# Feature Checklist

## Implemented In Scaffold

- Native SwiftUI app entry point.
- Sidebar-first browser shell.
- Space, folder, profile, tab, and split-view models.
- Space-scoped essentials/favorites and pinned tab metadata.
- Native command bar with URL/search routing and tab search.
- In-memory profile-scoped local history model, service, and command-bar history results.
- Minimal `WKWebView` host boundary.
- Persistent and private profile website data store selection.
- Default content rule list wiring.
- URL and download safety helpers.
- Native pending confirmation for external app and local file URL handoff.
- WebKit download delegate handling with native destination approval and risky download confirmation.
- Session snapshot model and JSON round-trip tests.
- SQLite-backed durable session persistence and startup restore through the private-state filtering boundary.
- App Sandbox entitlement draft.

## Not Yet Implemented

- Full native menu set.
- Drag-and-drop sidebar reordering and moves.
- Multi-tab web view lifecycle/pool and tab unloading.
- Split view UI.
- End-to-end WebKit download UI tests.
- Site permissions UI and storage.
- Durable local history persistence and history management UI.
- UI tests.
- Xcode project, signing, hardened runtime, notarization, and app bundle packaging.
