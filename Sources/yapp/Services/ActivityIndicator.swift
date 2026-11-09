import AppKit
import SwiftUI
import Combine

@MainActor
final class ActivityIndicator: ObservableObject {
    static let shared = ActivityIndicator()
    private var panel: NSPanel?
    @Published private(set) var visibleFrame: NSRect?
    private var observation: AnyCancellable?
    private var sound: NSSound?

    enum Presentation: Equatable {
        case hidden, preparing, recording, transcribing
        static func resolve(phase: DictationSession.Phase, waiting: Bool) -> Self {
            if phase == .recording { return .recording }
            if phase == .transcribing { return .transcribing }
            if waiting { return .preparing }
            return .hidden
        }
    }

    func start(session: DictationSession) {
        guard !CommandLine.arguments.contains("--smoke-audio") else { return }
        observation = session.$phase.combineLatest(session.$waitingForModel)
            .map { Presentation.resolve(phase: $0, waiting: $1) }
            .removeDuplicates()
            .sink { [weak self, weak session] presentation in
                guard let self, let session else { return }
                self.update(presentation: presentation, session: session)
            }
    }

    func refreshForTutorial() {
        let session = DictationSession.shared
        update(presentation: .resolve(phase: session.phase, waiting: session.waitingForModel), session: session)
    }

    private func update(presentation: Presentation, session: DictationSession) {
        let tutorialPreparing = FirstLaunchGuide.shared.practiceID != nil && !FirstLaunchGuide.shared.practice.isPrepared
        guard presentation != .hidden, !(presentation == .preparing && tutorialPreparing) else {
            panel?.orderOut(nil)
            visibleFrame = nil
            return
        }
        if panel == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 104, height: 38), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false
            panel.isFloatingPanel = true
            panel.becomesKeyOnlyIfNeeded = true
            panel.hidesOnDeactivate = false
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.contentView = NSHostingView(rootView: ActivityIndicatorView(session: session).padding(4))
            self.panel = panel
        }
        if panel?.isVisible != true, let screen = FirstLaunchGuide.shared.tutorialScreen ?? NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main {
            let visible = screen.visibleFrame
            panel?.setFrameOrigin(NSPoint(x: visible.midX - 52, y: visible.minY + 14))
        }
        panel?.level = FirstLaunchGuide.shared.practiceID != nil
            ? NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2) : .floating
        panel?.orderFrontRegardless()
        visibleFrame = panel?.frame
        sound?.stop()
        guard presentation == .recording || presentation == .transcribing else { return }
        sound = NSSound(named: NSSound.Name(presentation == .recording ? "Tink" : "Pop"))
        sound?.volume = 0.18
        sound?.play()
    }

    func shutdown() {
        observation?.cancel(); observation = nil
        sound?.stop(); sound = nil
        panel?.orderOut(nil); panel = nil
        visibleFrame = nil
    }
}
