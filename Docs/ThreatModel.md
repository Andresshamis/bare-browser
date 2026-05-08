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
- External app and `file://` links require confirmation rather than silent opening.
- Non-local HTTP pages are flagged as insecure transport.
- Download filenames are sanitized and risky executable-like extensions are classified.
- Persistent profile metadata stores a WebKit data store UUID; private profiles intentionally do not.
- Site permission decisions now pass through `SitePermissionPolicy`, which models camera, microphone, geolocation, notifications, autoplay, and pop-up/new-window behavior with conservative defaults.
- Pop-up/new-window requests and WebKit media-capture permission callbacks are routed through store state before any grant; unsupported permission kinds are denied with an explicit message.
- Autoplay is configured to require a user gesture by default.
- App Sandbox entitlement file includes only sandbox and outbound network client entitlement.
- A small `WKContentRuleList` blocks common tracker/ad endpoints without request interception hacks.

## Required Follow-Up

- Implement user-facing confirmation UI for external apps, local files, and risky downloads.
- Add `WKDownloadDelegate` destination handling with quarantine metadata where feasible.
- Extend site permission UI and persistence beyond the first in-memory camera, microphone, pop-up, and autoplay policy slice.
- Revisit geolocation and notification permissions if future macOS WebKit SDKs expose safe delegate callbacks.
- Add automated profile isolation tests using local web fixtures.
- Verify private browsing data removal with WebKit data store APIs.
- Add a no-telemetry policy section to README and settings.
