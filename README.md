# Meridian Browser

Meridian Browser is an open-source, native macOS browser project built with SwiftUI and WebKit.

The product direction is a sidebar-first browsing workflow with spaces, pinned tabs,
favorites/essentials, folders, profiles, split views, a native command bar, and
minimal top chrome. Meridian uses original branding, assets, text, and
implementation.

## Status

The repository now contains the first package-based macOS scaffold:

- `MeridianBrowser`: SwiftUI app entry point.
- `MeridianCore`: models, store, persistence services, security helpers, WebKit host, and native views.
- `MeridianBrowserTests`: unit tests for foundational behavior.

This is not a release package yet. Signing, hardened runtime packaging, UI tests,
and notarization require the next Xcode project/bundle setup slice.

The app restores public session state from a local SQLite store under Application
Support. Private browsing profiles and dependent tab metadata are filtered before
any session snapshot is written to disk.

Local history is currently in-memory and scoped to the active persistent profile
for command-bar search. Private browsing profile visits are not recorded, and
recorded history URLs strip userinfo, fragments, and known sensitive query
parameters before retention.

## Requirements

- macOS Tahoe 26.x or later
- Xcode 26.x with the macOS 26 SDK
- Swift 6.2 or later

## Build And Test

```sh
swift build
swift test
./script/build_and_run.sh
```

`script/build_and_run.sh` stages the SwiftPM GUI executable into
`dist/Meridian Browser.app` before launching it, which gives the app foreground
macOS bundle behavior that `swift run MeridianBrowser` does not reliably provide.
It also supports `--debug`, `--logs`, `--subsystem-logs`, and `--verify`.

## Privacy And Diagnostics

Meridian does not collect product analytics, browsing telemetry, page contents,
URLs, credentials, cookies, tokens, or private browsing data. The current app has
no analytics SDK, tracking endpoint, or network reporting path.

Developer diagnostics are local only. `script/build_and_run.sh --logs` streams
local OS log entries for the Meridian process, and `--subsystem-logs` streams
local OS log entries for Meridian's bundle subsystem. These modes do not send
diagnostic data off the machine.

## Documentation

- [Architecture](Docs/Architecture.md)
- [Threat Model](Docs/ThreatModel.md)
- [Feature Checklist](Docs/FeatureChecklist.md)
- [WebKit Limitations](Docs/WebKitLimitations.md)
- [Test Plan](Docs/TestPlan.md)
- [Release Checklist](Docs/ReleaseChecklist.md)

## License

Meridian Browser is released under the MIT License. See [LICENSE](LICENSE).
