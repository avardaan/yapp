import AppKit
import AVFoundation
import SwiftUI
import Combine

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
    let practice = TutorialPractice()
    var practiceID: UUID? { practice.id }
    private var panels: [NSPanel] = []
    private var timer: Timer?
    private var waitingReason: String?
    private var globalEscape: Any?
    private var localEscape: Any?
    private let defaults: UserDefaults
    private var manuallyRequested = false
    var isPending: Bool { timer != nil }

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    private let completionKey = "completedFirstLaunchGuide"

    func start() {
        guard !CommandLine.arguments.contains("--smoke-audio"),
              !CommandLine.arguments.contains("--about"),
              (!defaults.bool(forKey: completionKey) || CommandLine.arguments.contains("--show-guide")) else { return }
        manuallyRequested = false
        schedulePresentation()
    }

    /// Replay without clearing preferences or permission grants.
    func replay() {
        shutdown()
        manuallyRequested = true
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
        let phase = DictationSession.shared.phase
        if phase == .recording || phase == .transcribing || phase == .requestingPermission { reason = "dictation_busy" }
        else if !manuallyRequested && phase != .ready { reason = "model_not_ready" }
        else if !manuallyRequested && AVCaptureDevice.authorizationStatus(for: .audio) != .authorized { reason = "microphone_permission" }
        else if !manuallyRequested && !TextInsertion.allowed { reason = "accessibility_permission" }
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
        practice.begin()
        for screen in NSScreen.screens {
            let panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.ignoresMouseEvents = false
            panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.isReleasedWhenClosed = false
            let localAnchor = screen == targetScreen ? anchor.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY) : nil
            let canvas = GuideCanvas(frame: NSRect(origin: .zero, size: screen.frame.size), anchor: localAnchor,
                                     shortcut: FnShortcut.shared.selected.title, practice: practice)
            panel.contentView = canvas
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

    @discardableResult
    func receivePracticeText(_ text: String, for id: UUID) -> Bool {
        practice.receive(text, for: id)
    }

    func dismiss() {
        guard !panels.isEmpty else { return }
        Diagnostics.shared.record("onboarding.completed", category: "Onboarding")
        defaults.set(true, forKey: completionKey)
        shutdown()
    }

    func shutdown() {
        timer?.invalidate(); timer = nil
        if let id = practiceID { DictationSession.shared.cancelTutorial(id: id) }
        practice.end()
        panels.forEach { $0.close() }; panels.removeAll()
        if let globalEscape { NSEvent.removeMonitor(globalEscape) }
        if let localEscape { NSEvent.removeMonitor(localEscape) }
        globalEscape = nil; localEscape = nil
    }
}

/// A transient destination: closing or replaying invalidates any in-flight result.
@MainActor
final class TutorialPractice: ObservableObject {
    @Published private(set) var id: UUID?
    @Published private(set) var text = ""
    func begin() { text = ""; id = UUID() }
    func end() { id = nil; text = "" }
    @discardableResult
    func receive(_ text: String, for id: UUID) -> Bool {
        guard self.id == id else { return false }
        self.text += (self.text.isEmpty ? "" : "\n") + text
        return true
    }
}

final class GuideCanvas: NSView {
    private let anchor: NSRect?
    private let shortcut: String
    private let practice: TutorialPractice
    private var observations = Set<AnyCancellable>()
    private var phase = DictationSession.Phase.ready
    private let output = NSTextView()
    private let outputScroll = NSScrollView()
    private let closeHint = NSTextField(labelWithString: "Esc to close")
    private let keyVisual: NSHostingView<TutorialKeyVisual>
    private let gold = NSColor(srgbRed: 244/255, green: 178/255, blue: 65/255, alpha: 1)

    init(frame: NSRect, anchor: NSRect?, shortcut: String, practice: TutorialPractice) {
        self.anchor = anchor; self.shortcut = shortcut; self.practice = practice
        keyVisual = NSHostingView(rootView: TutorialKeyVisual(session: .shared, shortcut: shortcut))
        super.init(frame: frame)
        guard anchor != nil else { return }
        output.font = .systemFont(ofSize: 19)
        output.textColor = .white
        output.isEditable = false
        output.isSelectable = false
        output.drawsBackground = false
        output.isVerticallyResizable = true
        output.isHorizontallyResizable = false
        output.autoresizingMask = [.width]
        output.textContainerInset = .zero
        output.textContainer?.widthTracksTextView = true
        output.setAccessibilityLabel("Practice dictation")
        outputScroll.drawsBackground = false
        outputScroll.hasVerticalScroller = true
        outputScroll.scrollerStyle = .overlay
        outputScroll.documentView = output
        closeHint.font = .systemFont(ofSize: 12)
        closeHint.textColor = .white.withAlphaComponent(0.55)
        closeHint.alignment = .center
        closeHint.isHidden = true
        addSubview(outputScroll); addSubview(keyVisual); addSubview(closeHint)
        keyVisual.alphaValue = 0
        // First locate Yapp in the menu bar, then bring the single action into focus.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self else { return }
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { self.keyVisual.alphaValue = 1 }
            else {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.3
                    self.keyVisual.animator().alphaValue = 1
                }
            }
        }
        practice.$text.sink { [weak self] text in
            self?.output.string = text
            self?.closeHint.isHidden = text.isEmpty
            self?.output.scrollToEndOfDocument(nil)
            self?.needsDisplay = true
        }.store(in: &observations)
        DictationSession.shared.$phase.sink { [weak self] phase in
            self?.phase = phase
            self?.needsDisplay = true
        }.store(in: &observations)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var card: NSRect {
        guard let anchor else { return .zero }
        let width = min(430.0, bounds.width - 48)
        let height = min(340.0, bounds.height - 100)
        let x = min(max(24, anchor.midX - width + 35), bounds.width - width - 24)
        let top = max(height + 24, min(anchor.minY - 100, bounds.height - 115))
        return NSRect(x: x, y: top - height, width: width, height: height)
    }
    private var practiceBox: NSRect {
        NSRect(x: card.minX + 22, y: card.minY + 24, width: card.width - 44, height: 104)
    }
    override func layout() {
        super.layout()
        guard anchor != nil else { return }
        outputScroll.frame = practiceBox.insetBy(dx: 15, dy: 14)
        output.setFrameSize(NSSize(width: outputScroll.contentSize.width, height: outputScroll.contentSize.height))
        keyVisual.frame = NSRect(x: card.midX - 56, y: card.maxY - 196, width: 112, height: 124)
        closeHint.frame = NSRect(x: card.minX + 22, y: card.minY + 5, width: card.width - 44, height: 16)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.64).setFill()
        bounds.fill()
        guard let anchor else { return }
        let spotlight = NSBezierPath(roundedRect: anchor.insetBy(dx: -9, dy: -5), xRadius: 9, yRadius: 9)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.compositingOperation = .clear
        spotlight.fill()
        NSGraphicsContext.restoreGraphicsState()
        gold.withAlphaComponent(0.8).setStroke()
        spotlight.lineWidth = 1.5; spotlight.stroke()

        let tip = NSPoint(x: anchor.midX, y: anchor.minY - 15)
        let arrow = NSBezierPath()
        arrow.move(to: NSPoint(x: card.midX, y: card.maxY + 16))
        arrow.curve(to: tip, controlPoint1: NSPoint(x: card.maxX - 10, y: card.maxY + 6),
                    controlPoint2: NSPoint(x: tip.x - 12, y: tip.y - 60))
        arrow.move(to: NSPoint(x: tip.x - 10, y: tip.y - 13))
        arrow.line(to: tip)
        arrow.line(to: NSPoint(x: tip.x + 9, y: tip.y - 15))
        gold.setStroke(); arrow.lineWidth = 2; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round; arrow.stroke()

        let surface = NSBezierPath(roundedRect: card, xRadius: 20, yRadius: 20)
        NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 0.98).setFill(); surface.fill()
        NSColor.white.withAlphaComponent(0.12).setStroke(); surface.lineWidth = 1; surface.stroke()
        drawText("Yapp lives up here.", rect: NSRect(x: card.minX + 22, y: card.maxY - 56, width: card.width - 44, height: 34),
                 font: .systemFont(ofSize: 25, weight: .semibold), color: .white)
        let box = NSBezierPath(roundedRect: practiceBox, xRadius: 10, yRadius: 10)
        NSColor.black.withAlphaComponent(0.22).setFill(); box.fill()
        gold.withAlphaComponent(phase == .recording ? 0.8 : 0.35).setStroke()
        box.lineWidth = 1; box.stroke()
        if practice.text.isEmpty {
            gold.setFill()
            NSRect(x: practiceBox.minX + 14, y: practiceBox.maxY - 37, width: 1.5, height: 21).fill()
        }
    }
    private func drawText(_ text: String, rect: NSRect, font: NSFont, color: NSColor) {
        (text as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: color])
    }
}

/// A visual key, not a clickable button: the physical shortcut is the tutorial's action.
private struct TutorialKeyVisual: View {
    @ObservedObject var session: DictationSession
    let shortcut: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let gold = Color(red: 244 / 255, green: 178 / 255, blue: 65 / 255)

    var body: some View {
        let pressed = session.shortcutOwnsRecording
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || pressed)) { timeline in
            let bob = reduceMotion || pressed ? 0 : sin(timeline.date.timeIntervalSinceReferenceDate * 3) * 3
            VStack(spacing: 12) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 19, weight: .light))
                    .foregroundStyle(gold.opacity(pressed ? 0 : 0.75))
                    .offset(y: bob)
                    .accessibilityHidden(true)
                ZStack {
                    RoundedRectangle(cornerRadius: 17)
                        .fill(.black.opacity(0.65))
                        .offset(y: 7)
                    RoundedRectangle(cornerRadius: 17)
                        .fill(pressed ? gold.opacity(0.14) : Color.white.opacity(0.08))
                        .overlay(RoundedRectangle(cornerRadius: 17)
                            .strokeBorder(pressed ? gold : Color.white.opacity(0.3), lineWidth: 1))
                        .overlay(Text(shortcut).font(.system(size: 27, weight: .medium))
                            .foregroundStyle(pressed ? gold : .white))
                        .offset(y: pressed ? 6 : 0)
                        .shadow(color: pressed ? gold.opacity(0.12) : .clear, radius: 12)
                }
                .frame(width: 78, height: 72)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: pressed)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hold \(shortcut) to try dictation")
        .accessibilityValue(pressed ? "Pressed" : "Not pressed")
        .allowsHitTesting(false)
    }
}
