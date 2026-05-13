# Release Checklist

- Add an Xcode project or generated project workflow for app bundle packaging.
- Set final bundle identifier and signing team.
- Enable App Sandbox.
- Enable Hardened Runtime.
- Keep entitlements minimal: outbound network client is expected; avoid file, camera, microphone, automation, Apple Events, and broad filesystem entitlements unless a feature requires them.
- Verify no secrets, credentials, cookies, private keys, or browsing data are stored in plaintext app storage.
- Confirm the GitHub Actions `CI / SwiftPM baseline` check passes on the release PR or branch.
- Run full unit and UI tests.
- Run signed Xcode app/UI smoke tests in a signing-capable environment until CI signing is explicitly configured.
- Run manual QA checklist.
- Profile launch, memory, CPU, hangs, and energy use.
- Archive, validate, notarize, staple, and verify Gatekeeper behavior.
- Document any App Store-specific limitations or review notes.
