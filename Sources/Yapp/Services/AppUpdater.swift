import AppKit
import Combine
import Sparkle

/// Sparkle is created only after an explicit menu action. Dictation never needs it.
@MainActor
final class AppUpdater: NSObject, ObservableObject, SPUUpdaterDelegate {
    static let shared = AppUpdater()
    @Published private(set) var canCheckForUpdates = true
    private var controller: SPUStandardUpdaterController?
    private var observation: AnyCancellable?

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        if controller == nil {
            let controller = SPUStandardUpdaterController(
                startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil
            )
            self.controller = controller
            // Enforce the manual-only product policy even if old defaults exist.
            controller.updater.automaticallyChecksForUpdates = false
            controller.updater.automaticallyDownloadsUpdates = false
            controller.startUpdater()
            observation = controller.updater.publisher(for: \.canCheckForUpdates)
                .sink { [weak self] available in self?.canCheckForUpdates = available }
        }
        NSApp.activate(ignoringOtherApps: true)
        controller?.checkForUpdates(nil)
    }

    func updaterShouldPromptForPermissionToCheck(forUpdates updater: SPUUpdater) -> Bool { false }

    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        guard updateCheck == .updates else {
            throw NSError(domain: "com.zeroslop.yapp.updates", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "yapp checks for updates only when requested."])
        }
    }
}
