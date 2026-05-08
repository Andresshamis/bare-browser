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
- URL scheme security decisions.
- Insecure HTTP detection.
- Download filename sanitization and risk classification.
- Site permission origin sanitization, supported/unsupported defaults, stored allow/deny decisions, and pending store state.
- Profile metadata for persistent and private browsing.
- Browser store relationships for spaces, folders, tabs, and session snapshots.

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
- UI or WebKit fixture tests for camera/microphone and pop-up prompts once the app test host exists.
