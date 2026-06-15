# Threat Model

## Assets

- Profile-isolated cookies, localStorage, IndexedDB, caches, service workers, and history metadata.
- Private browsing website data.
- Downloads and local files selected by the user.
- Browser session metadata such as tabs, spaces, folders, and profile names.
- Public-profile local history metadata.
- User trust in external app launches and permission prompts.

## Primary Threats

- Web content attempts to escape the web view through unsafe URL schemes, local files, downloads, or external app links.
- Profile data leaks between browsing identities.
- Private browsing writes persistent website data.
- Malicious downloads use confusing filenames or executable file types.
- Future user scripts or page modifications overreach their permissions.
- Persistence accidentally stores secrets, cookies, tokens, credentials, or private browsing data.

## Current Controls

- URL navigation is centralized in `URLSecurityPolicy`.
- Unsafe script/data schemes are blocked.
- External app and `file://` links create a pending native confirmation before any external handoff, retaining the target URL for approval while reducing source page context to a sanitized host or scheme label.
- Non-local HTTP main-frame navigations are HTTPS-first where practical: explicit opens and WebKit main-frame HTTP actions first attempt the HTTPS equivalent, while localhost and loopback URLs remain HTTP for local development. If a tracked HTTPS upgrade attempt falls back to HTTP, Bare Browser shows the generic insecure-transport status message without embedding the full URL.
- TLS certificate failures are not silently downgraded to HTTP fallback.
- WebKit downloads are routed through a native save-location confirmation before bytes are written.
- The download policy sanitizes candidate filenames, avoids existing destination paths, blocks installer-like packages, and requires explicit confirmation for executable-like extensions.
- Download source metadata published to UI/store state is reduced to a display host plus optional quarantine origin; full source URLs are not retained after WebKit callbacks.
- Completed downloads attempt to apply macOS quarantine metadata with only a privacy-safe source origin; failure is surfaced as a browser security message.
- Persistent profile metadata stores a WebKit data store UUID; private profiles intentionally do not.
- SQLite-backed session persistence saves only snapshots that pass through the private-state filtering boundary. Missing, unreadable, unsupported, or privacy-invalid saved state falls back to a seeded public session without logging saved URLs or private metadata.
- SQLite-backed local history records only HTTP(S) visits for non-ephemeral profiles. Private browsing profile visits are ignored before entering history state and filtered again before disk writes. Retained and restored history URLs strip userinfo, fragments, and known sensitive query parameters while preserving ordinary query items for page fidelity. Corrupt, unsupported, or privacy-invalid history stores recover with generic non-URL-bearing messages.
- Site permission decisions now pass through `SitePermissionPolicy`, which models camera, microphone, geolocation, notifications, autoplay, and pop-up/new-window behavior with conservative defaults.
- Public-profile allow/deny site permission decisions are included in session snapshots only after the persistence boundary verifies they are marked safe beyond the current session. Private-profile permission decisions remain session-only and are filtered from SQLite session payloads and repair-time scrubs.
- Active-site permission controls can change only supported camera, microphone, combined camera/microphone, and pop-up decisions through the same store policy path; unsupported and configuration-only permissions stay disabled rather than pretending to work.
- Pop-up/new-window requests and WebKit media-capture permission callbacks are routed through store state before any grant; unsupported permission kinds are denied with an explicit message.
- Autoplay is configured to require a user gesture by default.
- App Sandbox entitlement file includes only sandbox and outbound network client entitlement.
- A small `WKContentRuleList` blocks common tracker/ad endpoints without request interception hacks.
- Bare Browser does not collect product analytics, browsing telemetry, page contents, URLs, credentials, cookies, tokens, or private browsing data; developer log modes stream only local OS logs.

## Required Follow-Up

- Add end-to-end local WebKit download fixture tests once the Xcode UI test host exists.
- Add WebKit/UI fixture coverage for camera, microphone, and pop-up permission prompts once the signed UI test host exists.
- Expand history management UI beyond active-profile clearing and command-bar result deletion without weakening private-profile filtering.
- Revisit geolocation and notification permissions if future macOS WebKit SDKs expose safe delegate callbacks.
- Add automated profile isolation tests using local web fixtures.
- Verify private browsing data removal with WebKit data store APIs.
- Add a future in-app privacy/settings surface for the no-telemetry policy when settings UI exists.
