# Feature Checklist

## Implemented In Scaffold

- Native SwiftUI app entry point.
- Sidebar-first browser shell.
- Space, folder, profile, tab, and split-view models.
- Space-scoped essentials/favorites and pinned tab metadata, with sidebar and command-bar controls for moving existing tabs between regular Tabs, Pinned, and Essentials.
- Keyboard-accessible sidebar tab reordering within Essentials, Pinned, regular Tabs, and folder tab lists through context menus, native menu commands, and command-bar actions.
- Native command bar with URL/search routing, tab search, history results, and first browser actions for back, forward, reload/stop, and close tab.
- Native Navigate menu shortcuts for active browser Back, Forward, Reload, and Stop commands through a window-scoped command bridge.
- SQLite-backed profile-scoped local history model, service, command-bar history results, active-profile clear, and command-bar result deletion.
- Minimal `WKWebView` host boundary.
- Persistent and private profile website data store selection.
- Persistent profile creation and switching controls through the sidebar, native menu, and command bar.
- Default content rule list wiring.
- URL and download safety helpers.
- HTTPS-first upgrade attempts for non-local HTTP main-frame navigations, with controlled HTTP fallback warnings.
- Native pending confirmation for external app and local file URL handoff.
- WebKit download delegate handling with native destination approval and risky download confirmation.
- Opt-in HTTPS and loopback HTTP password-save prompt backed by local macOS Keychain storage for persistent profiles.
- Native password manager view with profile filtering and account/site search across saved persistent-profile accounts.
- Site permission policy with public-profile allow/deny persistence and private-profile session-only filtering.
- Active-site permission controls for camera, microphone, combined camera/microphone, and pop-up decisions.
- Session snapshot model and JSON round-trip tests.
- SQLite-backed durable session persistence and startup restore through the private-state filtering boundary.
- App Sandbox entitlement draft.

## Not Yet Implemented

- Full native menu set beyond the current browser navigation, profile, history, and tab basics.
- Pointer drag-and-drop sidebar reordering and cross-container moves.
- Profile rename/delete/import/export controls.
- Multi-tab web view lifecycle/pool and tab unloading.
- Split view UI.
- End-to-end WebKit download UI tests.
- End-to-end WebKit site permission UI tests.
- Full history library UI.
- UI tests.
- Xcode project, signing, hardened runtime, notarization, and app bundle packaging.
