# Release Checklist

- Keep `MeridianBrowser.xcodeproj` and the shared `MeridianBrowserApp` scheme building the app bundle and UI test host.
- Set final bundle identifier and signing team.
- Enable App Sandbox through `Configuration/MeridianBrowser.entitlements`.
- Enable Hardened Runtime for signed build products.
- Keep entitlements minimal: outbound network client is expected; avoid file, camera, microphone, automation, Apple Events, and broad filesystem entitlements unless a feature requires them.
- Verify signing and entitlements locally:
  `codesign -dvvv --entitlements :- DerivedData/xcode/Build/Products/Debug/MeridianBrowser.app`
  and `spctl -a -vv DerivedData/xcode/Build/Products/Debug/MeridianBrowser.app`.
- Confirm at least one valid code-signing identity exists with
  `security find-identity -p codesigning -v`; ad-hoc local signing does not prove
  final hardened runtime behavior.
- Verify no secrets, credentials, cookies, private keys, or browsing data are stored in plaintext app storage.
- Run full unit and UI tests.
- Run manual QA checklist.
- Profile launch, memory, CPU, hangs, and energy use.
- Archive, validate, notarize, staple, and verify Gatekeeper behavior.
- Document any App Store-specific limitations or review notes.
