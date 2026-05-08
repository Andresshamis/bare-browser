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

This is not a release package yet. Signing, hardened runtime packaging, UI tests,
and notarization require the next Xcode project/bundle setup slice.

## Requirements

- macOS Tahoe 26.x or later
- Xcode 26.x with the macOS 26 SDK
- Swift 6.2 or later

## Build And Test

```sh
swift build
swift test
swift run MeridianBrowser
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
