# Test Plan

## Automated Tests

Run:

```sh
swift test
```

GitHub Actions runs the baseline `CI / SwiftPM baseline` job for pull requests
targeting `dev` or `main` and for pushes to those branches. The job runs on a
macOS 26 runner and verifies:

- Swift and Xcode version traceability.
- `swift build`.
- `swift test`.
- `bash -n script/build_and_run.sh`.
- `git diff --check` whitespace hygiene against the pull request base or push
  range when available.

Current coverage:

- Address parsing, HTTPS-first bare-host resolution, and main-frame HTTP upgrade candidate policy.
- Search query routing.
- Command routing for URLs, search, spaces, folders, and keyboard-accessible tab reorder actions.
- Window-scoped browser navigation command bridge availability and dispatch gating for Back, Forward, Reload, and Stop.
- Profile-scoped local history recording, private-profile exclusion, URL normalization before retention/restore, restored duplicate collapse, scoped querying, command-bar history result activation, active-profile clear, and individual history delete.
- Persistent profile creation and switching, including default profile space/tab seeding, command-bar profile results, public session persistence, active-profile open-tab/history scoping, and site-permission scoping.
- URL scheme security decisions.
- Pending confirmation state for external app and local file URLs.
- Insecure HTTP detection, HTTPS-first explicit HTTP opens, controlled HTTP fallback warning publication, and stale insecure-status clearing after successful HTTPS updates.
- Download filename sanitization, risk classification, safe destination selection, and pending confirmation state.
- Password credential candidate sanitization, HTTPS plus loopback HTTP prompt gating, public-profile save confirmation, private-profile suppression, cancellation, profile-scoped account listing, password-manager tab reuse, and Keychain failure handling.
- Site permission origin sanitization, supported/unsupported defaults, stored allow/deny decisions, manual active-site allow/block/reset management, pending store state, restored public decisions, and private-profile persistence exclusion.
- Profile metadata for persistent and private browsing.
- Local WebKit fixture coverage proving persistent-profile separation and retention for cookies, localStorage, IndexedDB, Cache Storage, and service workers; private-profile in-memory lifetime; and space reassignment onto the destination profile store.
- Browser store relationships for spaces, folders, tabs, tab placement across Essentials/Pinned/Tabs, sidebar tab reordering within the current section or folder, and session snapshots.
- Session persistence boundary filtering and integrity repair for private profiles, duplicate identifiers, shared profile data stores, tab/space profile mismatches, invalid ownership graphs, private site permission decisions, dependent browser state, encoded payloads, and all-private fallback.
- SQLite session persistence save/load, missing-store fallback, unsupported/corrupt/unreadable store recovery with stale file removal, private session and private permission exclusion from the on-disk payload, and repair-time disk scrubbing.
- SQLite local history persistence save/load, private history exclusion from the on-disk payload, repair-time normalization/scrubbing, unsupported/corrupt recovery with stale file removal, and generic recovery messaging.

## Manual QA Targets

Run Google account isolation in both directions: University → Personal and Personal → University. Repeat after relaunch and after reassigning a space. Classify each observation separately as signed-in page state, Google account chooser state, URL `login_hint`/`authuser` hints, cached browser visuals, or macOS Password AutoFill suggestions.

- Google Docs
- YouTube
- GitHub
- Gmail or Outlook
- Figma
- Notion
- Banking-style login flow
- WebRTC test page
- File upload/download

Profile-isolation release acceptance additionally requires unique persistent website-store IDs, every tab resolving to its parent space's profile, no accepted stale callback after reassignment, no previous-profile snapshot flash, private-session disposal passing, and a clean full test run.

## Required Future Tests

- UI tests for creating spaces, folders, profiles, opening tabs, switching tabs, restoring sessions, and split view.
- CI coverage for signed Xcode app builds and UI smoke tests once issue #4 / PR #12 provides a signing-capable app/UI test host and the owner approves CI signing credentials.
- Signed-app lifecycle coverage proving private website data does not survive private-profile/window teardown.
- Broader history management UI tests once the signed app/UI test host can cover menus and command-bar context actions.
- UI coverage proving native Back, Forward, Reload, and Stop menu shortcuts reach the active WebKit view once the signed app/UI test host can cover app menus.
- UI coverage for pointer drag-and-drop sidebar reordering and cross-container tab moves after keyboard/menu reordering coverage is backed by a signed app/UI test host.
- End-to-end WebKit download fixture tests for delegate callbacks, save panel behavior, destination handling, quarantine metadata, and risky extension confirmation.
- SwiftUI/UI coverage proving the browser status row remains visible, dismissible, and VoiceOver reachable.
- End-to-end WebKit fixture tests proving main-frame HTTP link clicks attempt HTTPS first and fall back only for tracked upgrade attempts.
- UI or WebKit fixture tests for camera/microphone and pop-up prompts once the app test host exists.
