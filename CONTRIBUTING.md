# Contributing

Thanks for helping improve Lumen Browser.

## Development Setup

Requirements:

- macOS Tahoe 26.x or later.
- Xcode 26.x with the macOS 26 SDK.
- Swift 6.2 or later.

Run the baseline checks before opening a pull request:

```sh
swift build
swift test
bash -n script/build_and_run.sh
git diff --check
```

To launch the app as a foreground macOS bundle:

```sh
./script/build_and_run.sh
```

## Project Structure

- `Sources/MeridianBrowser`: SwiftUI app entry point and native menus.
- `Sources/MeridianCore`: browser models, stores, services, security policy, WebKit integration, and views.
- `Tests/MeridianBrowserTests`: unit tests.
- `Docs`: architecture, threat model, release checklist, test plan, and WebKit limitations.

The public product name is Lumen Browser. The Swift package and modules still use the historical `Meridian*` names.

## Pull Requests

Keep pull requests focused and include tests for behavior changes. Security-sensitive changes should update `Docs/ThreatModel.md` or `Docs/TestPlan.md` when the control surface changes.

Good pull requests usually include:

- A concise problem statement.
- The implementation approach.
- Tests run locally.
- Screenshots or notes for UI changes.
- Any privacy, persistence, WebKit, or profile-isolation implications.

## Security

Do not report vulnerabilities in public issues. See `SECURITY.md`.

## Assets

Do not add third-party branding, icons, images, fonts, or generated assets unless the source and license are documented. First-party project assets live under `Resources/`.
