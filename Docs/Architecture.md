# Lumen Browser Architecture

Lumen Browser is a native macOS, SwiftUI-first, WebKit-based browser. The early codebase is package-first so model, security, command routing, and WebKit boundary code can build and test before release packaging is added.

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

- Profiles carry stable `websiteDataStoreID` values. Persistent profiles use `WKWebsiteDataStore(forIdentifier:)`; private profiles reuse one `.nonPersistent()` store for the lifetime of the private profile. If imported persistent metadata is missing a store identifier, the model repairs it from the stable profile ID rather than using WebKit's shared default store.
- User-facing persistent profile creation goes through `BrowserStore.createPersistentProfileWithInitialSpace(name:colorHex:)`, which creates and selects the profile's first space. Additional spaces can be assigned through the space customizer, with confirmation before their tabs reload in the destination profile. Private profile creation remains separate and session-only.
- A web-content session is identified by its tab, parent space, effective profile, and website data-store ID. Web views, callbacks, and cached snapshots are discarded when that identity changes, preventing stale content from a previous profile from being reused.
- A tab's effective profile is always resolved from its parent space through `BrowserStore.profileContext(for:)`. The serialized tab profile field is compatibility metadata only; snapshots normalize it and startup repair fixes it before any web view is created.
- `BrowserStore.snapshot(...)` is the live runtime state shape. Disk persistence uses `SQLiteSessionPersistenceStore`, which atomically stores one encoded snapshot only after routing through `SessionPersistenceBoundary` to filter private state and repair duplicate identifiers, shared data stores, tab/space profile mismatches, ownership lists, selections, and dependent objects. For ambiguous shared stores, the oldest profile retains the store and later profiles receive clean identifiers without copying or deleting the shared data.
- Privacy-safe isolation diagnostics contain only build/OS metadata, object counts, repair counts, invariant names, and hashes of selected UUIDs. The last repair report is retained locally for support; it never includes URLs, account/profile names, cookies, page contents, emails, or credentials.
- App startup loads the SQLite session snapshot from Application Support. Missing, unreadable, unsupported, or privacy-invalid saved state falls back to `SessionSnapshotFactory.initial(...)` with a generic in-app message and no URL-bearing diagnostics.
- Favorites/essentials are currently space-scoped. They are stored on `BrowserSpace.favoriteTabIDs` so each space can have its own persistent anchors; `BrowserStore.setTabPlacement(...)` keeps Essentials, Pinned, regular Tabs, and folder membership mutually exclusive when a user moves an existing tab.
- Local history uses `LocalHistoryStore` plus `SQLiteLocalHistoryPersistenceStore`. It records only HTTP(S) visits for non-ephemeral profiles, normalizes retained URLs by stripping userinfo, fragments, and known sensitive query parameters, collapses restored duplicate profile/URL entries deterministically, and scopes command-bar history queries to the active profile. Private profile visits are ignored at the service/store boundary and filtered again before disk writes.
- The app lazily creates WebKit sessions and retains a bounded least-recently-used set of recent tab sessions. Every reuse check compares the full web-content identity.
- The command bar is native SwiftUI. It routes direct URLs, search queries, persistent profile creation/switching, active-profile open-tab results, active-profile history results, and initial creation commands.

## Near-Term Gaps

- Add an Xcode project for app bundle identity, signing, UI tests, and release packaging.
- Expand the history management surface beyond active-profile clear and command-bar result deletion.
- Expand `WKNavigationDelegate`, `WKUIDelegate`, and `WKDownloadDelegate` handling for permissions, downloads, popups, and TLS/authentication edge cases.
- Add drag-and-drop and reorder support for tabs, spaces, and folders.
