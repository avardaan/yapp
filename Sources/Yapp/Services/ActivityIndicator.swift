import AppKit
import SwiftUI
import Combine

@MainActor
final class ActivityIndicator {
    static let shared = ActivityIndicator()
    private var panel: NSPanel?
    private var observation: AnyCancellable?
    private var sound: NSSound?

    func start(session: DictationSession) {
        guard !CommandLine.arguments.contains("--smoke-audio") else { return }
        observation = session.$phase.removeDuplicates().sink { [weak self, weak session] phase in
            guard let self, let session else { return }
            self.update(phase: phase, session: session)
        }
    }

    private func update(phase: DictationSession.Phase, session: DictationSession) {
        guard phase == .recording || phase == .transcribing else {
            panel?.orderOut(nil)
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
        if phase == .recording, let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main {
            let visible = screen.visibleFrame
            panel?.setFrameOrigin(NSPoint(x: visible.midX - 52, y: visible.minY + 14))
        }
        panel?.orderFrontRegardless()
        sound?.stop()
        sound = NSSound(named: NSSound.Name(phase == .recording ? "Tink" : "Pop"))
        sound?.volume = 0.18
        sound?.play()
    }

    func shutdown() {
        observation?.cancel(); observation = nil
        sound?.stop(); sound = nil
        panel?.orderOut(nil); panel = nil
    }
}
