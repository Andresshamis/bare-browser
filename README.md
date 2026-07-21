# Bare Browser

Bare Browser is an open-source, native macOS browser project built with SwiftUI
and WebKit.

It exists because a certain kind of browser user got left hanging.

Arc proved that browsers did not have to be rows of tabs stapled to the top of a
window. It made browsing feel spatial, personal, and a little more like a real
workspace. Then The Browser Company shifted its focus to Dia, and Arc moved into
maintenance mode: still running, still receiving security/Chromium updates, but
no longer the active product with a future roadmap. For people who had built
their day around that model, that left a very specific hole.

There are interesting alternatives. Zen Browser is promising. Orion has real Mac
energy. Safari is solid. But none of them quite scratch this itch for me: a
browser that is open source, sidebar-first, WebKit-based, SwiftUI/AppKit-native,
and shaped like it actually belongs on macOS instead of feeling like a
cross-platform skin.

Bare Browser is the reaction to that gap.

It is not an Arc clone. It uses original branding, assets, text, and
implementation. The goal is to keep the part that mattered: spaces,
pinned/essential tabs, folders, profiles, split views, a native command bar,
minimal top chrome, and a calm Mac app sensibility.

The bet is simple: a browser can be opinionated without being noisy, powerful
without becoming a cockpit, and native without giving up the weird ideas that
made recent browser experiments feel alive.

Context:

- The Browser Company's 2025
  [letter to Arc members](https://browsercompany.substack.com/p/letter-to-arc-members-2025).
- The Verge's coverage of
  [Arc feature development stopping](https://www.theverge.com/news/674603/arc-browser-development-stopped-dia-browser-company).

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

Persistent profiles can be created from the sidebar profile menu, native menu,
or command bar. Creation also creates and selects the profile's first space;
additional spaces can be reassigned with an explicit confirmation before their
tabs reload in the destination profile. Private profiles remain session-only.

Local history is stored in a separate SQLite database under Application Support
and scoped to persistent profiles for command-bar search. Private browsing
profile visits are not recorded or written to disk, restored history is
normalized before use, and recorded history URLs strip userinfo, fragments, and
known sensitive query parameters before retention. The app includes native
actions to clear the active profile's history and delete individual command-bar
history results.

## Requirements

- macOS Tahoe 26.x or later
- Xcode 26.x with the macOS 26 SDK
- Swift 6.2 or later

## Repository Notes

The public product name is Bare Browser. The Swift package, module names, and
some internal symbols still use the historical `Meridian*` naming.

First-party app assets live under `Resources/`. Do not add third-party assets
without documenting their source and license.

## Build And Test

```sh
swift build
swift test
./script/build_and_run.sh
```

`script/build_and_run.sh` stages the SwiftPM GUI executable into
`dist/Bare Browser.app` before launching it, which gives the app foreground
macOS bundle behavior that `swift run MeridianBrowser` does not reliably provide.
It also supports `--debug`, `--logs`, `--subsystem-logs`, and `--verify`.

GitHub Actions runs the baseline CI suite on pull requests targeting `dev` or
`main` and on pushes to those branches. The `CI / SwiftPM baseline` check uses a
macOS 26 runner, prints the active Swift/Xcode versions, runs `swift build`,
`swift test`, `bash -n script/build_and_run.sh`, and checks diff whitespace.
Signing, UI smoke tests, notarization, and release packaging remain manual until
the Xcode app/UI test host and owner-approved signing setup are available.

## Privacy And Diagnostics

Bare Browser does not collect product analytics, browsing telemetry, page contents,
URLs, cookies, tokens, or private browsing data. Website passwords are stored only
after explicit user confirmation, only for persistent profiles, and only in the
local macOS Keychain with this-device-only accessibility. The current app has no
analytics SDK, tracking endpoint, or network reporting path.

Developer diagnostics are local only. `script/build_and_run.sh --logs` streams
local OS log entries for the Bare Browser process, and `--subsystem-logs` streams
local OS log entries for Bare Browser's bundle subsystem. These modes do not send
diagnostic data off the machine.

## Documentation

- [Architecture](Docs/Architecture.md)
- [Threat Model](Docs/ThreatModel.md)
- [Feature Checklist](Docs/FeatureChecklist.md)
- [WebKit Limitations](Docs/WebKitLimitations.md)
- [Test Plan](Docs/TestPlan.md)
- [Release Checklist](Docs/ReleaseChecklist.md)

## Contributing And Security

- [Contributing](CONTRIBUTING.md)
- [Security Policy](SECURITY.md)
- [Support](SUPPORT.md)
- [Code of Conduct](CODE_OF_CONDUCT.md)

## License

Bare Browser is released under the MIT License. See [LICENSE](LICENSE).
