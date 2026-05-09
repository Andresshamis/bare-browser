# Test Plan

## Automated Tests

Run:

```sh
swift test
```

Current coverage:

- Address parsing and HTTPS-first host resolution.
- Search query routing.
- Command routing for URLs, search, spaces, and folders.
- Profile-scoped local history recording, private-profile exclusion, scoped querying, and command-bar history result activation.
- URL scheme security decisions.
- Pending confirmation state for external app and local file URLs.
- Insecure HTTP detection.
- Download filename sanitization, risk classification, safe destination selection, and pending confirmation state.
- Site permission origin sanitization, supported/unsupported defaults, stored allow/deny decisions, and pending store state.
- Profile metadata for persistent and private browsing.
- Browser store relationships for spaces, folders, tabs, and session snapshots.
- Session persistence boundary filtering for private profiles, dependent browser state, encoded payloads, and all-private fallback.
- SQLite session persistence save/load, missing-store fallback, unsupported/corrupt/unreadable store recovery with stale file removal, private session exclusion from the on-disk payload, and repair-time disk scrubbing.

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
- Durable local history persistence tests once history storage is added.
- End-to-end WebKit download fixture tests for delegate callbacks, save panel behavior, destination handling, quarantine metadata, and risky extension confirmation.
- UI or WebKit fixture tests for camera/microphone and pop-up prompts once the app test host exists.
