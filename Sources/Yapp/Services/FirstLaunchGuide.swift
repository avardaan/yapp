import AppKit
import AVFoundation
import SwiftUI

/// Reports the real status-item position, including when macOS reorders the menu bar.
struct StatusItemAnchor: NSViewRepresentable {
    func makeNSView(context: Context) -> AnchorView { AnchorView() }
    func updateNSView(_ view: AnchorView, context: Context) { view.report() }

    final class AnchorView: NSView {
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); report() }
        override func layout() { super.layout(); report() }
        func report() {
            guard let window, bounds.width > 0, bounds.height > 0 else { return }
            let rect = window.convertToScreen(convert(bounds, to: nil))
            DispatchQueue.main.async { FirstLaunchGuide.shared.anchor = rect }
        }
    }
}

@MainActor
final class FirstLaunchGuide {
    static let shared = FirstLaunchGuide()
    var anchor: NSRect?
    private var panels: [NSPanel] = []
    private var timer: Timer?
    private var waitingReason: String?
    private var globalEscape: Any?
    private var localEscape: Any?
    private let defaults = UserDefaults.standard
    private let completionKey = "completedFirstLaunchGuide"

    func start() {
        guard !CommandLine.arguments.contains("--smoke-audio"),
              !CommandLine.arguments.contains("--about"),
              (!defaults.bool(forKey: completionKey) || CommandLine.arguments.contains("--show-guide")) else { return }
        schedulePresentation()
    }

    /// Replay without clearing preferences or permission grants.
    func replay() {
        shutdown()
        schedulePresentation()
    }

    private func schedulePresentation() {
        timer?.invalidate()
        // Let the menu close before presenting the guide.
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.showIfReady() }
        }
    }

    private func showIfReady() {
        let reason: String?
        if DictationSession.shared.phase != .ready { reason = "model_not_ready" }
        else if AVCaptureDevice.authorizationStatus(for: .audio) != .authorized { reason = "microphone_permission" }
        else if !TextInsertion.allowed { reason = "accessibility_permission" }
        else { reason = nil }
        if let reason { waiting(reason); return }
        // MenuBarExtra can render its label without hosting the background NSView.
        // Its own status window still gives the real menu-item bounds.
        let position = anchor ?? NSApp.windows.first(where: {
            $0.className.contains("StatusBar") && $0.frame.width > 0 && $0.frame.height <= 50
        })?.frame
        guard let anchor = position,
              let targetScreen = NSScreen.screens.first(where: { $0.frame.intersects(anchor) }) else {
            waiting("menu_anchor"); return
        }
        waitingReason = nil
        Diagnostics.shared.record("onboarding.shown", category: "Onboarding")
        timer?.invalidate(); timer = nil
        for screen in NSScreen.screens {
            let panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.isReleasedWhenClosed = false
            let localAnchor = screen == targetScreen ? anchor.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY) : nil
            panel.contentView = GuideCanvas(frame: NSRect(origin: .zero, size: screen.frame.size), anchor: localAnchor, shortcut: FnShortcut.shared.selected.title)
            panel.orderFrontRegardless()
            panels.append(panel)
        }
        globalEscape = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return }
            MainActor.assumeIsolated { self?.dismiss() }
        }
        localEscape = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                MainActor.assumeIsolated { self?.dismiss() }
                return nil
            }
            return event
        }
    }

    private func waiting(_ reason: String) {
        guard waitingReason != reason else { return }
        waitingReason = reason
        Diagnostics.shared.record("onboarding.waiting", category: "Onboarding", detail: true, fields: ["reason": reason])
    }

    /// Starting dictation also consumes a guide that is still waiting to appear.
    func completeFromShortcut() {
        guard timer != nil || !panels.isEmpty else { return }
        Diagnostics.shared.record("onboarding.completed", category: "Onboarding", fields: ["reason": "dictation_started"])
        defaults.set(true, forKey: completionKey)
        shutdown()
    }

    func dismiss() {
        guard !panels.isEmpty else { return }
        Diagnostics.shared.record("onboarding.completed", category: "Onboarding")
        defaults.set(true, forKey: completionKey)
        shutdown()
    }

    func shutdown() {
        timer?.invalidate(); timer = nil
        panels.forEach { $0.close() }; panels.removeAll()
        if let globalEscape { NSEvent.removeMonitor(globalEscape) }
        if let localEscape { NSEvent.removeMonitor(localEscape) }
        globalEscape = nil; localEscape = nil
    }
}

private final class GuideCanvas: NSView {
    private let anchor: NSRect?
    private let shortcut: String
    init(frame: NSRect, anchor: NSRect?, shortcut: String) {
        self.anchor = anchor; self.shortcut = shortcut
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.64).setFill()
        bounds.fill()
        guard let anchor else { return }
        let gold = NSColor(srgbRed: 244/255, green: 178/255, blue: 65/255, alpha: 1)
        let spotlight = NSBezierPath(roundedRect: anchor.insetBy(dx: -9, dy: -5), xRadius: 9, yRadius: 9)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.compositingOperation = .clear
        spotlight.fill()
        NSGraphicsContext.restoreGraphicsState()
        gold.withAlphaComponent(0.8).setStroke()
        spotlight.lineWidth = 1.5; spotlight.stroke()

        let width = min(360.0, bounds.width - 48)
        let x = min(max(24, anchor.midX - width + 35), bounds.width - width - 24)
        let y = min(anchor.minY - 230, bounds.height - 250)
        let tip = NSPoint(x: anchor.midX, y: anchor.minY - 15)
        let arrow = NSBezierPath()
        arrow.move(to: NSPoint(x: x + width * 0.55, y: y + 155))
        arrow.curve(to: tip, controlPoint1: NSPoint(x: x + width * 0.9, y: y + 150),
                    controlPoint2: NSPoint(x: tip.x - 12, y: tip.y - 65))
        arrow.move(to: NSPoint(x: tip.x - 10, y: tip.y - 13))
        arrow.line(to: tip)
        arrow.line(to: NSPoint(x: tip.x + 9, y: tip.y - 15))
        gold.setStroke(); arrow.lineWidth = 2; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round; arrow.stroke()

        drawText("Your control center.", rect: NSRect(x: x, y: y + 110, width: width, height: 34), font: .systemFont(ofSize: 25, weight: .semibold), color: .white)
        drawText("Yapp lives up here.", rect: NSRect(x: x, y: y + 76, width: width, height: 28), font: .systemFont(ofSize: 17), color: .white.withAlphaComponent(0.8))
        drawText("Hold \(shortcut) to exit and start yapping.", rect: NSRect(x: x, y: y + 22, width: width, height: 44), font: .systemFont(ofSize: 17, weight: .medium), color: gold)
        drawText("Release to insert.  ·  Esc to skip", rect: NSRect(x: x, y: y - 5, width: width, height: 25), font: .systemFont(ofSize: 13), color: .white.withAlphaComponent(0.6))
    }
    private func drawText(_ text: String, rect: NSRect, font: NSFont, color: NSColor) {
        (text as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: color])
    }
}
