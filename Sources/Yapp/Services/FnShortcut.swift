import AppKit
import CoreGraphics
import OSLog

@MainActor
final class FnShortcut: ObservableObject {
    static let shared = FnShortcut()
    @Published private(set) var selected: DictationShortcut
    @Published private(set) var status = "Shortcut starting…" {
        didSet { if oldValue != status { Diagnostics.shared.record("listener.status", category: "Shortcut", fields: ["status": self.status]) } }
    }
    // Keep the proven event-tap backend available for a controlled comparison.
    private let usesAccessibilityListener = !CommandLine.arguments.contains("--input-monitoring-listener")
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var timer: Timer?
    private var state = ShortcutKeyState()
    private var pressedAt: Date?
    private let defaults = UserDefaults.standard
    private let systemDefaults = UserDefaults(suiteName: "com.apple.HIToolbox")!

    private init() {
        selected = DictationShortcut(rawValue: UserDefaults.standard.string(forKey: "dictationShortcut") ?? "fn") ?? .fn
    }

    func start() {
        guard !CommandLine.arguments.contains("--smoke-audio") else { return }
        if selected == .fn { configureGlobeKey() }
        attachIfAllowed()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.poll() }
        }
        if usesAccessibilityListener {
            if !AXIsProcessTrusted() && !defaults.bool(forKey: "requestedShortcutAccessibility") {
                defaults.set(true, forKey: "requestedShortcutAccessibility")
                TextInsertion.requestPermission()
            }
        } else if !CGPreflightListenEventAccess() && !defaults.bool(forKey: "requestedInputMonitoring") {
            requestPermission()
        }
    }

    func requestPermission() {
        if selected == .fn { configureGlobeKey() }
        defaults.set(true, forKey: "requestedInputMonitoring")
        _ = CGRequestListenEventAccess()
        attachIfAllowed()
    }

    var inputMonitoringAllowed: Bool { CGPreflightListenEventAccess() }

    func select(_ shortcut: DictationShortcut) {
        guard shortcut != selected else { return }
        detach()
        if selected == .fn { restoreGlobeAction() }
        selected = shortcut
        defaults.set(shortcut.rawValue, forKey: "dictationShortcut")
        if shortcut == .fn { configureGlobeKey() }
        attachIfAllowed()
    }

    // Preserve the user's original single-press Globe action before disabling it.
    // This persists across quitting Yapp, matching an installed shortcut choice.
    private func configureGlobeKey() {
        guard !defaults.bool(forKey: "globeActionConfigured") else { return }
        if let old = systemDefaults.object(forKey: "AppleFnUsageType") {
            defaults.set(old, forKey: "originalGlobeAction")
        } else { defaults.removeObject(forKey: "originalGlobeAction") }
        systemDefaults.set(0, forKey: "AppleFnUsageType")
        if systemDefaults.synchronize() {
            defaults.set(true, forKey: "globeActionConfigured")
        }
    }

    private func restoreGlobeAction() {
        guard defaults.bool(forKey: "globeActionConfigured") else { return }
        if let old = defaults.object(forKey: "originalGlobeAction") {
            systemDefaults.set(old, forKey: "AppleFnUsageType")
        } else { systemDefaults.removeObject(forKey: "AppleFnUsageType") }
        systemDefaults.synchronize()
        defaults.removeObject(forKey: "globeActionConfigured")
        defaults.removeObject(forKey: "originalGlobeAction")
        status = "Previous Globe action restored"
    }

    func openPermissionSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") else { return }
        NSWorkspace.shared.open(url)
    }

    private func attachIfAllowed() {
        if usesAccessibilityListener { attachAccessibilityMonitor(); return }
        attachInputMonitoringTap()
    }

    private func attachAccessibilityMonitor() {
        guard globalMonitor == nil, localMonitor == nil else { return }
        guard AXIsProcessTrusted() else {
            status = "Accessibility required"
            return
        }
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.handleAppKitEvent(event) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.handleAppKitEvent(event) }
            return event
        }
        guard globalMonitor != nil, localMonitor != nil else {
            detach()
            status = "Shortcut listener unavailable"
            return
        }
        Diagnostics.shared.record("listener.attached", category: "Shortcut", detail: true, fields: ["backend": "accessibility"])
        status = "Hold \(selected.title) to talk"
    }

    private func handleAppKitEvent(_ event: NSEvent) {
        let action: ShortcutKeyState.Action?
        switch event.type {
        case .flagsChanged:
            let flags = CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue))
            action = state.flagsChanged(keyCode: Int64(event.keyCode), isDown: flags.contains(selected.flag), triggerKeyCode: selected.keyCode)
        case .keyDown: action = state.otherKeyPressed()
        default: return
        }
        apply(action)
    }

    private func attachInputMonitoringTap() {
        guard tap == nil else { return }
        guard CGPreflightListenEventAccess() else {
            status = "Input Monitoring required"
            return
        }
        let mask = (CGEventMask(1) << CGEventType.flagsChanged.rawValue) | (CGEventMask(1) << CGEventType.keyDown.rawValue)
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let controller = Unmanaged<FnShortcut>.fromOpaque(context).takeUnretainedValue()
                // The source is installed only on the main run loop.
                MainActor.assumeIsolated { controller.handle(type: type, event: event) }
                return Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            status = "Restart Yapp after permission"
            return
        }
        tap = port
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) }
        CGEvent.tapEnable(tap: port, enable: true)
        status = "Hold \(selected.title) to talk"
    }

    private func handle(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            cancelHold()
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        let action: ShortcutKeyState.Action?
        if type == .flagsChanged {
            action = state.flagsChanged(keyCode: event.getIntegerValueField(.keyboardEventKeycode), isDown: event.flags.contains(selected.flag), triggerKeyCode: selected.keyCode)
        } else if type == .keyDown { action = state.otherKeyPressed() }
        else { return }
        apply(action)
    }

    private func apply(_ action: ShortcutKeyState.Action?) {
        switch action {
        case .pressed:
            Diagnostics.shared.record("shortcut.pressed", category: "Shortcut", detail: true)
            pressedAt = Date()
            DictationSession.shared.shortcutPressed()
        case .released:
            Diagnostics.shared.record("shortcut.released", category: "Shortcut", detail: true)
            pressedAt = nil
            DictationSession.shared.shortcutReleased()
        case .cancelled:
            Diagnostics.shared.record("shortcut.cancelled", category: "Shortcut", detail: true)
            pressedAt = nil
            DictationSession.shared.cancelShortcut()
        case nil: break
        }
    }

    private func cancelHold() { apply(state.reset()) }

    private func poll() {
        let allowed = usesAccessibilityListener ? AXIsProcessTrusted() : CGPreflightListenEventAccess()
        if !allowed {
            detach()
            status = usesAccessibilityListener ? "Accessibility required" : "Input Monitoring required"
            return
        }
        attachIfAllowed()
        if let tap, !CGEvent.tapIsEnabled(tap: tap) {
            cancelHold()
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        if state.held {
            let stillHeld = CGEventSource.flagsState(.combinedSessionState).contains(selected.flag)
            // Discard if release was lost, the session was locked, or a key sticks.
            if !stillHeld || (pressedAt.map { Date().timeIntervalSince($0) > 120 } ?? false) { cancelHold() }
        }
    }

    private func detach() {
        cancelHold()
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        source = nil
        if let tap { CFMachPortInvalidate(tap) }
        tap = nil
    }

    func shutdown() { timer?.invalidate(); timer = nil; detach() }
}
