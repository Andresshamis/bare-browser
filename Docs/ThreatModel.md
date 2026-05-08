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
- App Sandbox entitlement file includes only sandbox and outbound network client entitlement.
- A small `WKContentRuleList` blocks common tracker/ad endpoints without request interception hacks.

## Required Follow-Up

- Implement user-facing confirmation UI for external apps, local files, and risky downloads.
- Add `WKDownloadDelegate` destination handling with quarantine metadata where feasible.
- Add site permission state for camera, microphone, geolocation, notifications, popups, downloads, and autoplay.
- Add automated profile isolation tests using local web fixtures.
- Verify private browsing data removal with WebKit data store APIs.
- Add a no-telemetry policy section to README and settings.
