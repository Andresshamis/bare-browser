# Test Plan

## Automated Tests

Run:

```sh
swift test
xcodebuild -project MeridianBrowser.xcodeproj -scheme MeridianBrowserApp -configuration Debug -derivedDataPath DerivedData/xcode -destination 'platform=macOS,arch=arm64' test
```

Current coverage:

- Address parsing and HTTPS-first host resolution.
- Search query routing.
- Command routing for URLs, search, spaces, and folders.
- URL scheme security decisions.
- Insecure HTTP detection.
- Download filename sanitization and risk classification.
- Profile metadata for persistent and private browsing.
- Browser store relationships for spaces, folders, tabs, and session snapshots.
- Xcode UI smoke host for launching the signed app bundle and observing the
  first browser window.

The Xcode UI test host requires a valid local macOS code-signing identity.
Ad-hoc signing can compile the runner and test bundle, but local execution may
fail before tests run if the runner and bundle cannot load under compatible Team
IDs.

## Manual QA Targets

- Google Docs
- YouTube
- GitHub
- Gmail or Outlook
- Figma
- Notion
- Banking-style login flow
- WebRTC test page
- File upload/download

## Required Future Tests

- UI tests for creating spaces, folders, profiles, opening tabs, switching tabs, restoring sessions, and split view.
- Local web fixture tests proving cookies/localStorage do not leak between profiles.
- Private browsing persistence tests proving website data does not survive window/session close.
- Download delegate tests for filenames, destination handling, quarantine, and risky extensions.
