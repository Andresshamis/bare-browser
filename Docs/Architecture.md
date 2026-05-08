# Meridian Browser Architecture

Meridian Browser is a native macOS, SwiftUI-first, WebKit-based browser. The early codebase is package-first so model, security, command routing, and WebKit boundary code can build and test before release packaging is added.

## Targets

- `MeridianBrowser`: SwiftUI app entry point and native command menus.
- `MeridianCore`: Browser models, stores, security services, WebKit integration, and SwiftUI views.
- `MeridianBrowserTests`: Unit tests for model relationships, address parsing, command routing, profile metadata, session snapshots, and security helpers.

## Boundaries

- `Models/`: Stable value models for tabs, spaces, folders, profiles, split views, and session snapshots.
- `Stores/`: Main-window observable state and user actions.
- `Services/`: Address resolution, command routing, snapshot seeding, and future persistence services.
- `Security/`: URL and download safety policies. Security-sensitive decisions should stay here instead of view code.
- `WebKit/`: `WKWebView` configuration, profile website data stores, content blocking, and the SwiftUI/AppKit host bridge.
- `Views/`: Sidebar-first browser shell, command bar, and browser content surfaces.

## Current Design Decisions

- Profiles carry stable `websiteDataStoreID` values. Persistent profiles use `WKWebsiteDataStore.dataStore(forIdentifier:)`; private profiles use `.nonPersistent()`.
- Favorites/essentials are currently space-scoped. They are stored on `BrowserSpace.favoriteTabIDs` so each space can have its own persistent anchors.
- The app lazily creates a `WKWebView` for the selected tab only. A later web view pool can keep recent tabs warm without instantiating all saved tabs.
- The command bar is native SwiftUI. It routes direct URLs, search queries, tab search, and initial creation commands.

## Near-Term Gaps

- Add durable persistence using SwiftData, SQLite, or Core Data.
- Add an Xcode project for app bundle identity, signing, UI tests, and release packaging.
- Expand `WKNavigationDelegate`, `WKUIDelegate`, and `WKDownloadDelegate` handling for permissions, downloads, popups, and TLS/authentication edge cases.
- Add drag-and-drop and reorder support for tabs, spaces, and folders.
