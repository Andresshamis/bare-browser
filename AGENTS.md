# Repository Guidance

## Product and Toolchain

- The public product name is **Lumen Browser**. Keep the historical
  `MeridianBrowser`, `MeridianCore`, and other `Meridian*` names for Swift
  packages, targets, modules, and existing internal symbols.
- This is a SwiftPM-first native macOS app using SwiftUI, AppKit, and WebKit.
- The supported development baseline is macOS 26, Xcode 26, and Swift 6.2.
- Launch the foreground app bundle with `./script/build_and_run.sh`. Do not use
  `swift run MeridianBrowser` as a substitute for app-bundle behavior.

## Repository Layout

- `Sources/MeridianBrowser`: application entry point and native menus.
- `Sources/MeridianCore`: models, stores, services, security policy,
  persistence, WebKit integration, and SwiftUI views.
- `Tests/MeridianBrowserTests`: Swift unit and integration tests.
- `DebugFixtures`: local-only HTML fixtures for WebKit behavior.
- `Configuration`: app entitlements and related packaging configuration.
- `Resources`: first-party application assets.
- `Docs`: architecture, threat model, test plan, release checklist, and known
  WebKit limitations.
- `script/build_and_run.sh`: build, stage, sign, verify, launch, and local-log
  workflow for `dist/Lumen Browser.app`.

## Validation

Run the repository baseline before handing off code changes:

```sh
swift build
swift test
bash -n script/build_and_run.sh
git diff --check
```

- Add or update tests for behavior changes.
- Run the baseline independently on each affected branch when a cherry-pick,
  merge, or conflict resolution produces branch-specific code.
- Use `./script/build_and_run.sh --verify` when app-bundle packaging or signing
  behavior changes and the local environment can perform the check.
- Signing, notarization, and full UI smoke tests remain manual unless the
  repository gains an explicitly configured signing-capable test host.

## Branch and Git Workflow

- Both `dev` and `main` are CI branches.
- Do not assume `dev` and `main` are byte-identical, fast-forwardable, or based
  on the same commit hashes. Promotion and squash history can make equivalent
  work appear as different commits.
- Before cross-branch work, inspect:

```sh
git status --short --branch
git branch -vv
git log --left-right --graph --oneline dev...main
```

- To apply one local change to both divergent branches, commit it once and
  normally cherry-pick that commit onto the other branch. Resolve conflicts in
  the target branch's native structure; do not merge entire branches merely to
  copy a single change.
- Re-run tests on the target branch after any conflict resolution, then return
  to the user's original branch unless they request otherwise.
- Use concise, imperative, sentence-case commit subjects consistent with the
  existing history, for example `Fix website microphone capture`.
- Keep commits focused and public-history-ready. Do not commit `.build`,
  `dist`, `.codex`, credentials, signing keys, profiles, or other ignored local
  state.
- A request to commit does not authorize a push. Push only when the user asks.

## Security, Privacy, and WebKit

- Keep entitlements minimal. For a capability that requires macOS permission,
  inspect all relevant surfaces: packaged-app entitlements, local signing
  entitlements when present, generated Info.plist usage descriptions, tests,
  and documentation.
- Treat browser state, URLs, cookies, tokens, credentials, profile identities,
  and private browsing data as sensitive. Do not add telemetry or remote
  diagnostics.
- Persistent state must pass through the existing privacy filtering and repair
  boundaries. Private-profile state must remain session-only and must not reach
  disk.
- Preserve profile isolation across web views, callbacks, cached snapshots,
  history, permissions, credentials, and website data stores.
- Route security-sensitive WebKit behavior through explicit policy/store state.
  If WebKit cannot support a feature safely, document the limitation instead
  of simulating unsafe compatibility.
- Security-sensitive changes should update `Docs/ThreatModel.md` or
  `Docs/TestPlan.md` when the control surface or acceptance criteria change.
  Update `Docs/WebKitLimitations.md` for platform limitations or capability
  dependencies.

## Assets and Documentation

- Use first-party assets under `Resources`.
- Do not add third-party branding, icons, images, fonts, or generated assets
  without documenting their source and license.
- Keep user-facing copy branded as Lumen Browser while retaining established
  internal Meridian names.
- Keep README, contributor guidance, feature status, tests, and security
  documentation aligned with implemented behavior.
