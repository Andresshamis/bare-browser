import AppKit
import SwiftUI

struct WindowTitlebarInteractionZone: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowTitlebarInteractionNSView {
        WindowTitlebarInteractionNSView()
    }

    func updateNSView(_ nsView: WindowTitlebarInteractionNSView, context: Context) {}
}

final class WindowTitlebarInteractionNSView: NSView {
    private var mouseDownEvent: NSEvent?

    override var acceptsFirstResponder: Bool {
        true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else {
            return
        }

        if event.clickCount >= 2 {
            mouseDownEvent = nil
            performTitlebarDoubleClickAction(on: window)
            return
        }

        mouseDownEvent = event
    }

    override func mouseDragged(with event: NSEvent) {
        guard let mouseDownEvent,
              let window else {
            return
        }

        self.mouseDownEvent = nil
        window.performDrag(with: mouseDownEvent)
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownEvent = nil
    }

    private func performTitlebarDoubleClickAction(on window: NSWindow) {
        let action = UserDefaults.standard
            .string(forKey: "AppleActionOnDoubleClick")?
            .lowercased()

        switch action {
        case "minimize":
            window.miniaturize(nil)
        case "none":
            return
        default:
            window.toggleMeridianTitlebarZoom()
        }
    }
}

@MainActor
private enum WindowTitlebarZoomState {
    static var previousFrames: [ObjectIdentifier: CGRect] = [:]
    static var animationTokens: [ObjectIdentifier: UUID] = [:]
    static var animationTasks: [ObjectIdentifier: Task<Void, Never>] = [:]
}

@MainActor
private extension NSWindow {
    func toggleMeridianTitlebarZoom() {
        guard let screen = screen ?? NSScreen.main else {
            performZoom(nil)
            return
        }

        let key = ObjectIdentifier(self)
        let targetFrame = screen.visibleFrame

        if frame.isApproximatelyEqual(to: targetFrame),
           let previousFrame = WindowTitlebarZoomState.previousFrames[key] {
            WindowTitlebarZoomState.previousFrames[key] = nil
            animateMeridianFrameChange(to: previousFrame, key: key)
            return
        }

        WindowTitlebarZoomState.previousFrames[key] = frame
        animateMeridianFrameChange(to: targetFrame, key: key)
    }

    func animateMeridianFrameChange(to targetFrame: CGRect, key: ObjectIdentifier) {
        let startFrame = frame
        let token = UUID()
        let duration: TimeInterval = 0.18

        WindowTitlebarZoomState.animationTasks[key]?.cancel()
        WindowTitlebarZoomState.animationTokens[key] = token

        WindowTitlebarZoomState.animationTasks[key] = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            let startTime = CACurrentMediaTime()
            while !Task.isCancelled {
                let elapsed = CACurrentMediaTime() - startTime
                let linearProgress = min(max(elapsed / duration, 0), 1)
                let easedProgress = CGFloat(1 - pow(1 - linearProgress, 3))
                setFrame(
                    startFrame.interpolated(to: targetFrame, progress: easedProgress),
                    display: true,
                    animate: false
                )

                if linearProgress >= 1 {
                    break
                }

                try? await Task.sleep(nanoseconds: 8_333_333)
            }

            if !Task.isCancelled {
                setFrame(targetFrame, display: true, animate: false)
            }

            if WindowTitlebarZoomState.animationTokens[key] == token {
                WindowTitlebarZoomState.animationTokens[key] = nil
                WindowTitlebarZoomState.animationTasks[key] = nil
            }
        }
    }
}

private extension CGRect {
    func isApproximatelyEqual(to other: CGRect, tolerance: CGFloat = 2) -> Bool {
        abs(origin.x - other.origin.x) <= tolerance
            && abs(origin.y - other.origin.y) <= tolerance
            && abs(size.width - other.size.width) <= tolerance
            && abs(size.height - other.size.height) <= tolerance
    }

    func interpolated(to other: CGRect, progress: CGFloat) -> CGRect {
        CGRect(
            x: origin.x + (other.origin.x - origin.x) * progress,
            y: origin.y + (other.origin.y - origin.y) * progress,
            width: size.width + (other.size.width - size.width) * progress,
            height: size.height + (other.size.height - size.height) * progress
        )
    }
}
