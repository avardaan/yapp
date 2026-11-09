import AppKit
import AVFoundation
import SwiftUI
import Combine

@MainActor
final class FirstLaunchGuide {
    static let shared = FirstLaunchGuide()
    private(set) var tutorialScreen: NSScreen?
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
        guard let targetScreen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else { return }
        tutorialScreen = targetScreen
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
            let canvas = GuideCanvas(frame: NSRect(origin: .zero, size: screen.frame.size),
                                     screenOrigin: screen.frame.origin, isPrimary: screen == targetScreen,
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
        tutorialScreen = nil
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

enum TutorialStage: Equatable {
    case prompt, preparing, listening, processing, result
    static func resolve(phase: DictationSession.Phase, hasText: Bool) -> Self {
        switch phase {
        case .recording: return .listening
        case .transcribing: return .processing
        case .loading, .requestingPermission: return .preparing
        case .ready, .failed: return hasText ? .result : .prompt
        }
    }
}

/// Dim the desktop, with practice content on the same screen as the real activity pill.
final class GuideCanvas: NSView {
    private let screenOrigin: NSPoint
    private let isPrimary: Bool
    private let practice: TutorialPractice
    private var observations = Set<AnyCancellable>()
    private var phase = DictationSession.Phase.ready
    private var displayedText = ""
    private var floatyFrame: NSRect?
    private let output = NSTextView()
    private let outputScroll = NSScrollView()
    private let closeHint = NSTextField(labelWithString: "Esc to close")
    private let instruction: NSHostingView<TutorialInstruction>
    private let gold = NSColor(srgbRed: 244/255, green: 178/255, blue: 65/255, alpha: 1)

    init(frame: NSRect, screenOrigin: NSPoint, isPrimary: Bool, shortcut: String, practice: TutorialPractice,
         session: DictationSession? = nil, activityFrames: AnyPublisher<NSRect?, Never>? = nil) {
        let session = session ?? DictationSession.shared
        self.screenOrigin = screenOrigin; self.isPrimary = isPrimary; self.practice = practice
        instruction = NSHostingView(rootView: TutorialInstruction(session: session, practice: practice, shortcut: shortcut))
        super.init(frame: frame)
        guard isPrimary else { return }
        output.font = .systemFont(ofSize: 22)
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
        addSubview(outputScroll); addSubview(instruction); addSubview(closeHint)
        practice.$text.sink { [weak self] text in
            self?.displayedText = text
            self?.output.string = text
            self?.output.scrollToEndOfDocument(nil)
            self?.refresh()

        }.store(in: &observations)
        session.$phase.sink { [weak self] phase in
            self?.phase = phase
            self?.refresh()
        }.store(in: &observations)
        (activityFrames ?? ActivityIndicator.shared.$visibleFrame.eraseToAnyPublisher()).sink { [weak self] frame in
            guard let self else { return }
            self.floatyFrame = frame?.offsetBy(dx: -self.screenOrigin.x, dy: -self.screenOrigin.y)
            self.needsDisplay = true
        }.store(in: &observations)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func refresh() {
        closeHint.isHidden = stage != .result
        needsDisplay = true
    }

    static func practiceFrame(in bounds: NSRect) -> NSRect {
        let width = min(580.0, max(1, bounds.width - 64))
        let height = min(140.0, bounds.height * 0.25)
        return NSRect(x: bounds.midX - width / 2, y: bounds.midY - 35, width: width, height: height)
    }
    private var practiceBox: NSRect { Self.practiceFrame(in: bounds) }
    private var stage: TutorialStage { .resolve(phase: phase, hasText: !displayedText.isEmpty) }

    override func layout() {
        super.layout()
        guard isPrimary else { return }
        outputScroll.frame = practiceBox.insetBy(dx: 20, dy: 18)
        output.setFrameSize(NSSize(width: outputScroll.contentSize.width, height: outputScroll.contentSize.height))
        instruction.frame = NSRect(x: practiceBox.minX, y: practiceBox.maxY + 26, width: practiceBox.width, height: 64)
        closeHint.frame = NSRect(x: practiceBox.minX, y: practiceBox.minY - 112, width: practiceBox.width, height: 18)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.64).setFill()
        bounds.fill()
        guard isPrimary else { return }
        let box = NSBezierPath(roundedRect: practiceBox, xRadius: 14, yRadius: 14)
        NSColor(srgbRed: 0.08, green: 0.08, blue: 0.09, alpha: 0.95).setFill(); box.fill()
        (stage == .listening ? gold.withAlphaComponent(0.55) : NSColor.white.withAlphaComponent(0.18)).setStroke()
        box.lineWidth = 1; box.stroke()
        if displayedText.isEmpty {
            gold.setFill()
            NSRect(x: practiceBox.minX + 20, y: practiceBox.maxY - 44, width: 1.5, height: 25).fill()
        }

        if stage == .listening, let frame = floatyFrame, bounds.intersects(frame) {
            let label = NSRect(x: min(max(24, frame.midX - 190), bounds.maxX - 404),
                               y: min(frame.maxY + 60, practiceBox.minY - 54), width: 380, height: 44)
            drawText("Yappman’s listening.", rect: label, size: 18, weight: .medium)
            drawText("Speak, then release to transcribe.", rect: label.offsetBy(dx: 0, dy: -24), size: 14,
                     color: .white.withAlphaComponent(0.65))
            let start = NSPoint(x: label.midX + 35, y: label.minY - 12)
            let tip = NSPoint(x: frame.midX, y: frame.maxY + 7)
            drawArrow(from: start, to: tip,
                      control1: NSPoint(x: start.x, y: tip.y + 24), control2: NSPoint(x: tip.x, y: tip.y + 25))
        } else if stage == .result {
            let label = NSRect(x: practiceBox.midX - 180, y: practiceBox.minY - 70, width: 360, height: 28)
            drawText("That’s your voice, in text.", rect: label, size: 18, weight: .medium)
            let tip = NSPoint(x: practiceBox.minX + 12, y: practiceBox.maxY - 33)
            let outside = max(16, practiceBox.minX - 46)
            drawArrow(from: NSPoint(x: label.minX + 16, y: label.midY + 7), to: tip,
                      control1: NSPoint(x: outside, y: label.maxY + 10), control2: NSPoint(x: outside, y: tip.y))
        }
    }

    private func drawArrow(from start: NSPoint, to tip: NSPoint, control1: NSPoint, control2: NSPoint) {
        let arrow = NSBezierPath()
        arrow.move(to: start); arrow.curve(to: tip, controlPoint1: control1, controlPoint2: control2)
        let angle = atan2(tip.y - control2.y, tip.x - control2.x)
        for offset in [-0.5, 0.5] {
            arrow.move(to: tip)
            arrow.line(to: NSPoint(x: tip.x - cos(angle + offset) * 10, y: tip.y - sin(angle + offset) * 10))
        }
        gold.withAlphaComponent(0.8).setStroke()
        arrow.lineWidth = 1.5; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round; arrow.stroke()
    }

    private func drawText(_ text: String, rect: NSRect, size: CGFloat,
                          weight: NSFont.Weight = .regular, color: NSColor = .white) {
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
        (text as NSString).draw(in: rect, withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight),
                                                         .foregroundColor: color, .paragraphStyle: paragraph])
    }
}

private struct TutorialInstruction: View {
    @ObservedObject var session: DictationSession
    @ObservedObject var practice: TutorialPractice
    let shortcut: String
    private var stage: TutorialStage { .resolve(phase: session.phase, hasText: !practice.text.isEmpty) }

    var body: some View {
        Group {
            if stage == .processing {
                Text("Transcribing on your Mac…").font(.system(size: 22, weight: .medium))
            } else {
                HStack(spacing: 12) {
                    Text(stage == .listening ? "Keep holding" : stage == .preparing ? "Getting ready" : stage == .result ? "Hold" : "Press and hold")
                    TutorialKeyVisual(session: session, shortcut: shortcut)
                    if stage == .result { Text("to try again") }
                }
                .font(.system(size: stage == .result ? 19 : 22, weight: .medium))
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Mirrors the MacBook Globe/fn legends; the physical key remains the only action.
private struct TutorialKeyVisual: View {
    @ObservedObject var session: DictationSession
    let shortcut: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let gold = Color(red: 244 / 255, green: 178 / 255, blue: 65 / 255)

    var body: some View {
        let pressed = session.shortcutOwnsRecording
        ZStack {
            RoundedRectangle(cornerRadius: 9).fill(.black.opacity(0.7)).offset(y: 4)
            RoundedRectangle(cornerRadius: 9)
                .fill(pressed ? gold.opacity(0.15) : Color.white.opacity(0.1))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(pressed ? gold : Color.white.opacity(0.35), lineWidth: 1))
                .overlay {
                    if shortcut == "Fn" {
                        ZStack {
                            Image(systemName: "globe").font(.system(size: 13, weight: .regular))
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading).padding(7)
                            Text("fn").font(.system(size: 12, weight: .medium))
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(7)
                        }
                        .foregroundStyle(pressed ? gold : .white)
                    } else {
                        Text(shortcut).font(.system(size: 14, weight: .medium)).foregroundStyle(pressed ? gold : .white)
                    }
                }
                .offset(y: pressed ? 3 : 0)
        }
        .frame(width: 50, height: 45)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: pressed)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hold \(shortcut) to try dictation")
        .accessibilityValue(pressed ? "Pressed" : "Not pressed")
        .allowsHitTesting(false)
    }
}
