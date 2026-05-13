# WebKit Limitations

Meridian Browser uses `WKWebView`, not Safari's full browser process or Chromium. Known limitations must be visible in product and engineering decisions.

## Current Known Limitations

- Some Safari browser features are not public `WKWebView` APIs.
- Chrome extension compatibility is not available and should not be claimed.
- Safari Web Extensions require a dedicated extension architecture and are not part of this scaffold.
- Per-profile isolation depends on WebKit support for identified website data stores. Persistent profiles use `WKWebsiteDataStore.dataStore(forIdentifier:)`; private profiles use `.nonPersistent()`.
- Fine-grained permission APIs vary by macOS/WebKit version. In the macOS 26.2 SDK used for this slice, `WKUIDelegate` exposes media-capture permission callbacks for camera/microphone; Meridian routes those through `SitePermissionPolicy`.
- Public-profile allow/deny decisions for supported site permissions can persist in Meridian's session store. Private-profile permission decisions are session-only and filtered before disk writes.
- Meridian's active-site permission menu can manage only WebKit delegate-backed permissions. Unsupported or configuration-only permissions are shown as limited instead of writing ineffective per-site settings.
- Geolocation and notification permission prompts do not have equivalent public macOS `WKUIDelegate` callbacks in this SDK, so Meridian marks them unsupported and denies them conservatively until a safe API is available.
- Autoplay is controlled at `WKWebViewConfiguration` level by requiring a user gesture for media playback rather than by per-site WebKit callbacks.
- TLS error handling must never be bypassed silently. The scaffold does not yet add custom override UI.
- Web process lifecycle and memory pressure behavior are controlled partly by WebKit; Meridian should layer tab unloading and restore metadata on top.

## Engineering Rule

If WebKit cannot provide a browser feature safely, document the limitation and choose the safest supported behavior rather than faking compatibility.
