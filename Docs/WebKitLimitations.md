# WebKit Limitations

Meridian Browser uses `WKWebView`, not Safari's full browser process or Chromium. Known limitations must be visible in product and engineering decisions.

## Current Known Limitations

- Some Safari browser features are not public `WKWebView` APIs.
- Chrome extension compatibility is not available and should not be claimed.
- Safari Web Extensions require a dedicated extension architecture and are not part of this scaffold.
- Per-profile isolation depends on WebKit support for identified website data stores. Persistent profiles use `WKWebsiteDataStore.dataStore(forIdentifier:)`; private profiles use `.nonPersistent()`.
- Fine-grained permission APIs vary by macOS/WebKit version and need explicit implementation/testing.
- TLS error handling must never be bypassed silently. The scaffold does not yet add custom override UI.
- Web process lifecycle and memory pressure behavior are controlled partly by WebKit; Meridian should layer tab unloading and restore metadata on top.

## Engineering Rule

If WebKit cannot provide a browser feature safely, document the limitation and choose the safest supported behavior rather than faking compatibility.
