# WebKit Limitations

Lumen Browser uses `WKWebView`, not Safari's full browser process or Chromium. Known limitations must be visible in product and engineering decisions.

## Current Known Limitations

- Some Safari browser features are not public `WKWebView` APIs.
- Chrome extension compatibility is not available and should not be claimed.
- Safari Web Extensions require a dedicated extension architecture and are not part of this scaffold.
- Per-profile isolation depends on WebKit support for identified website data stores. Persistent profiles use `WKWebsiteDataStore(forIdentifier:)`; each private profile reuses one `.nonPersistent()` store until that private profile closes.
- macOS Password AutoFill suggestions can be surfaced by WebKit independently of Lumen Browser's profile-scoped Keychain credential store. These device-wide suggestions are outside the profile-isolation guarantee; webpage-specific suppression would be incomplete and fragile, so the UI distinguishes the two instead.
- Fine-grained permission APIs vary by macOS/WebKit version. In the macOS 26.2 SDK used for this slice, `WKUIDelegate` exposes media-capture permission callbacks for camera/microphone; Lumen Browser routes those through `SitePermissionPolicy`.
- Public-profile allow/deny decisions for supported site permissions can persist in Lumen Browser's session store. Private-profile permission decisions are session-only and filtered before disk writes.
- Lumen Browser's active-site permission menu can manage only WebKit delegate-backed permissions. Unsupported or configuration-only permissions are shown as limited instead of writing ineffective per-site settings.
- Geolocation and notification permission prompts do not have equivalent public macOS `WKUIDelegate` callbacks in this SDK, so Lumen Browser marks them unsupported and denies them conservatively until a safe API is available.
- Autoplay is controlled at `WKWebViewConfiguration` level by requiring a user gesture for media playback rather than by per-site WebKit callbacks.
- TLS error handling must never be bypassed silently. The scaffold does not yet add custom override UI.
- HTTPS-first fallback is scoped to tracked main-frame upgrade attempts. Certificate trust failures are not downgraded to HTTP; fixture coverage for WebKit delegate edge cases should be added once the signed UI test host is available.
- Web process lifecycle and memory pressure behavior are controlled partly by WebKit; Lumen Browser should layer tab unloading and restore metadata on top.

## Engineering Rule

If WebKit cannot provide a browser feature safely, document the limitation and choose the safest supported behavior rather than faking compatibility.
