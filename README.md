# Meridian Browser

Meridian Browser is an open-source, native macOS browser project built with SwiftUI and WebKit.

The product direction is a sidebar-first browsing workflow with spaces, pinned tabs,
favorites/essentials, folders, profiles, split views, a native command bar, and
minimal top chrome. Meridian uses original branding, assets, text, and
implementation.

## Status

The repository now contains the first package-based macOS scaffold:

- `MeridianBrowser`: SwiftUI app entry point.
- `MeridianCore`: models, store, security helpers, WebKit host, and native views.
- `MeridianBrowserTests`: unit tests for foundational behavior.
- `MeridianBrowser.xcodeproj`: native app bundle target, shared Xcode scheme,
  signing entitlements, and a UI test host.

This is not a release package yet. Final signing team configuration,
notarization, and distribution packaging remain release work.

## Requirements

- macOS Tahoe 26.x or later
- Xcode 26.x with the macOS 26 SDK
- Swift 6.2 or later

## Build And Test

```sh
swift build
swift test
./script/build_and_run.sh
./script/build_and_run.sh --verify
xcodebuild -project MeridianBrowser.xcodeproj -scheme MeridianBrowserApp -configuration Debug -derivedDataPath DerivedData/xcode build
xcodebuild -project MeridianBrowser.xcodeproj -scheme MeridianBrowserApp -configuration Debug -derivedDataPath DerivedData/xcode -destination 'platform=macOS,arch=arm64' test
```

`script/build_and_run.sh` stages the SwiftPM GUI executable into
`dist/Meridian Browser.app` before launching it, which gives the app foreground
macOS bundle behavior that `swift run MeridianBrowser` does not reliably provide.
It also supports `--debug`, `--logs`, `--telemetry`, and `--verify`.

The Xcode scheme builds `DerivedData/xcode/Build/Products/Debug/MeridianBrowser.app`
with `CFBundleDisplayName` set to `Meridian Browser`. UI test execution on macOS
requires a valid local code-signing identity so the XCTest runner and test bundle
load under compatible Team IDs; ad-hoc signing can build the host but may fail at
test launch.

To inspect local signing and entitlements:

```sh
APP=DerivedData/xcode/Build/Products/Debug/MeridianBrowser.app
codesign -dvvv --entitlements :- "$APP"
spctl -a -vv "$APP"
security find-identity -p codesigning -v
```

## Documentation

- [Architecture](Docs/Architecture.md)
- [Threat Model](Docs/ThreatModel.md)
- [Feature Checklist](Docs/FeatureChecklist.md)
- [WebKit Limitations](Docs/WebKitLimitations.md)
- [Test Plan](Docs/TestPlan.md)
- [Release Checklist](Docs/ReleaseChecklist.md)

## License

Meridian Browser is released under the MIT License. See [LICENSE](LICENSE).
