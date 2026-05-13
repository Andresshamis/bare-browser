# Meridian Browser Architecture

Meridian Browser is a native macOS, SwiftUI-first, WebKit-based browser. The early codebase is package-first so model, security, command routing, and WebKit boundary code can build and test before release packaging is added.

## Targets

- `MeridianBrowser`: SwiftUI app entry point and native command menus.
- `MeridianCore`: Browser models, stores, security services, WebKit integration, and SwiftUI views.
- `MeridianBrowserTests`: Unit tests for model relationships, address parsing, command routing, profile metadata, session snapshots, and security helpers.

## Boundaries

- `Models/`: Stable value models for tabs, spaces, folders, profiles, split views, local history entries, command-bar results, and session snapshots.
- `Stores/`: Main-window observable state and user actions.
- `Services/`: Address resolution, command routing, profile-scoped local history, snapshot seeding, SQLite-backed session persistence, and SQLite-backed local history persistence.
- `Security/`: URL and download safety policies. Security-sensitive decisions should stay here instead of view code.
- `WebKit/`: `WKWebView` configuration, profile website data stores, content blocking, and the SwiftUI/AppKit host bridge.
- `Views/`: Sidebar-first browser shell, command bar, and browser content surfaces.

## Current Design Decisions

- Profiles carry stable `websiteDataStoreID` values. Persistent profiles use `WKWebsiteDataStore.dataStore(forIdentifier:)`; private profiles use `.nonPersistent()`. If imported persistent metadata is missing a store identifier, the model repairs it from the stable profile ID rather than using WebKit's shared default store.
- Persistent profile creation goes through `BrowserStore.createPersistentProfile(name:)`, which creates a stable public profile and selects or seeds a default space/tab context. Sidebar, native menu, and command-bar profile switching all route through `BrowserStore.switchProfile(_:)`. Private profile creation remains separate and session-only.
- `BrowserStore.snapshot(...)` is the live runtime state shape. Disk persistence uses `SQLiteSessionPersistenceStore`, which stores one encoded snapshot only after routing through `SessionPersistenceBoundary` to filter private profiles and dependent spaces, folders, tabs, split views, selected IDs, and restoration metadata before encoding.
- App startup loads the SQLite session snapshot from Application Support. Missing, unreadable, unsupported, or privacy-invalid saved state falls back to `SessionSnapshotFactory.initial(...)` with a generic in-app message and no URL-bearing diagnostics.
- Favorites/essentials are currently space-scoped. They are stored on `BrowserSpace.favoriteTabIDs` so each space can have its own persistent anchors; `BrowserStore.setTabPlacement(...)` keeps Essentials, Pinned, regular Tabs, and folder membership mutually exclusive when a user moves an existing tab.
- Local history uses `LocalHistoryStore` plus `SQLiteLocalHistoryPersistenceStore`. It records only HTTP(S) visits for non-ephemeral profiles, normalizes retained URLs by stripping userinfo, fragments, and known sensitive query parameters, collapses restored duplicate profile/URL entries deterministically, and scopes command-bar history queries to the active profile. Private profile visits are ignored at the service/store boundary and filtered again before disk writes.
- The app lazily creates a `WKWebView` for the selected tab only. A later web view pool can keep recent tabs warm without instantiating all saved tabs.
- The command bar is native SwiftUI. It routes direct URLs, search queries, persistent profile creation/switching, active-profile open-tab results, active-profile history results, and initial creation commands.

## Near-Term Gaps

- Add runtime WebKit fixture coverage proving profile cookies/localStorage isolation and private browsing cleanup once the signed UI test host is available.
- Add an Xcode project for app bundle identity, signing, UI tests, and release packaging.
- Expand the history management surface beyond active-profile clear and command-bar result deletion.
- Expand `WKNavigationDelegate`, `WKUIDelegate`, and `WKDownloadDelegate` handling for permissions, downloads, popups, and TLS/authentication edge cases.
- Add drag-and-drop and reorder support for tabs, spaces, and folders.
