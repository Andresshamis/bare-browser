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
- Command routing for URLs, search, spaces, and folders.
- Window-scoped browser navigation command bridge availability and dispatch gating for Back, Forward, Reload, and Stop.
- Profile-scoped local history recording, private-profile exclusion, URL normalization before retention/restore, restored duplicate collapse, scoped querying, command-bar history result activation, active-profile clear, and individual history delete.
- Persistent profile creation and switching, including default profile space/tab seeding, command-bar profile results, public session persistence, active-profile open-tab/history scoping, and site-permission scoping.
- Private browsing session lifecycle creation and discard, including visible app-state selection, dependent space/folder/tab/split cleanup, public fallback selection, session-only permission cleanup, private history candidate removal, and continued exclusion from persistent profile search.
- URL scheme security decisions.
- Pending confirmation state for external app and local file URLs.
- Insecure HTTP detection, HTTPS-first explicit HTTP opens, controlled HTTP fallback warning publication, and stale insecure-status clearing after successful HTTPS updates.
- Download filename sanitization, risk classification, safe destination selection, and pending confirmation state.
- Site permission origin sanitization, supported/unsupported defaults, stored allow/deny decisions, manual active-site allow/block/reset management, pending store state, restored public decisions, and private-profile persistence exclusion.
- Profile metadata for persistent and private browsing.
- Browser store relationships for spaces, folders, tabs, tab placement across Essentials/Pinned/Tabs, and session snapshots.
- Session persistence boundary filtering for private profiles, private site permission decisions, dependent browser state, encoded payloads, and all-private fallback.
- SQLite session persistence save/load, missing-store fallback, unsupported/corrupt/unreadable store recovery with stale file removal, private session and private permission exclusion from the on-disk payload, and repair-time disk scrubbing.
- SQLite local history persistence save/load, private history exclusion from the on-disk payload, repair-time normalization/scrubbing, unsupported/corrupt recovery with stale file removal, and generic recovery messaging.

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
- CI coverage for signed Xcode app builds and UI smoke tests once issue #4 / PR #12 provides a signing-capable app/UI test host and the owner approves CI signing credentials.
- Local web fixture tests proving cookies/localStorage do not leak between profiles.
- Private browsing WebKit fixture tests proving website data does not survive private session close.
- Broader history management UI tests once the signed app/UI test host can cover menus and command-bar context actions.
- UI coverage proving native Back, Forward, Reload, and Stop menu shortcuts reach the active WebKit view once the signed app/UI test host can cover app menus.
- End-to-end WebKit download fixture tests for delegate callbacks, save panel behavior, destination handling, quarantine metadata, and risky extension confirmation.
- SwiftUI/UI coverage proving the browser status row remains visible, dismissible, and VoiceOver reachable.
- End-to-end WebKit fixture tests proving main-frame HTTP link clicks attempt HTTPS first and fall back only for tracked upgrade attempts.
- UI or WebKit fixture tests for camera/microphone and pop-up prompts once the app test host exists.
