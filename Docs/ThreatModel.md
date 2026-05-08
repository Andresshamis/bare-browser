# Threat Model

## Assets

- Profile-isolated cookies, localStorage, IndexedDB, caches, service workers, and history metadata.
- Private browsing website data.
- Downloads and local files selected by the user.
- Browser session metadata such as tabs, spaces, folders, and profile names.
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
- Non-local HTTP pages are flagged as insecure transport.
- WebKit downloads are routed through a native save-location confirmation before bytes are written.
- The download policy sanitizes candidate filenames, avoids existing destination paths, blocks installer-like packages, and requires explicit confirmation for executable-like extensions.
- Download source metadata published to UI/store state is reduced to a display host plus optional quarantine origin; full source URLs are not retained after WebKit callbacks.
- Completed downloads attempt to apply macOS quarantine metadata with only a privacy-safe source origin; failure is surfaced as a browser security message.
- Persistent profile metadata stores a WebKit data store UUID; private profiles intentionally do not.
- Session persistence has an explicit boundary that filters private profiles and dependent browser metadata before disk encoding.
- Site permission decisions now pass through `SitePermissionPolicy`, which models camera, microphone, geolocation, notifications, autoplay, and pop-up/new-window behavior with conservative defaults.
- Pop-up/new-window requests and WebKit media-capture permission callbacks are routed through store state before any grant; unsupported permission kinds are denied with an explicit message.
- Autoplay is configured to require a user gesture by default.
- App Sandbox entitlement file includes only sandbox and outbound network client entitlement.
- A small `WKContentRuleList` blocks common tracker/ad endpoints without request interception hacks.

## Required Follow-Up

- Add end-to-end local WebKit download fixture tests once the Xcode UI test host exists.
- Add the durable persistence backend and ensure all writes use the private-state filtering boundary.
- Extend site permission UI and persistence beyond the first in-memory camera, microphone, pop-up, and autoplay policy slice.
- Revisit geolocation and notification permissions if future macOS WebKit SDKs expose safe delegate callbacks.
- Add automated profile isolation tests using local web fixtures.
- Verify private browsing data removal with WebKit data store APIs.
- Add a no-telemetry policy section to README and settings.
