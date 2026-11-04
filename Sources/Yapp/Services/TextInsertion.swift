import AppKit
import ApplicationServices

@MainActor
final class TextInsertion {
    struct Target {
        let processID: pid_t
        let element: AXUIElement
    }

    static var allowed: Bool { AXIsProcessTrusted() }

    static func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func captureTarget() -> Target? {
        guard allowed, let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier else { return nil }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let element = unsafeBitCast(value, to: AXUIElement.self)
        var subrole: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole)
        guard subrole as? String != "AXSecureTextField" else { return nil }
        return Target(processID: app.processIdentifier, element: element)
    }

    static func stillFocused(_ target: Target) -> Bool {
        guard let current = captureTarget() else { return false }
        return current.processID == target.processID && CFEqual(current.element, target.element)
    }

    // Return nil after sending Paste, or an explanatory status if insertion is unsafe or unavailable.
    // Never paste into a field/app the user switched to during transcription.
    static func insert(_ text: String, into target: Target?, dictation: Int? = nil) async -> String? {
        let text = DictationText.clean(text)
        guard !text.isEmpty else { log("empty_text", dictation: dictation); return "No speech detected" }
        guard allowed else { log("accessibility_missing", dictation: dictation); return "Enable Accessibility to insert; transcript available in Copy Last Transcript." }
        guard let target, stillFocused(target) else { log(target == nil ? "no_safe_target" : "focus_changed", dictation: dictation); return "Input focus changed; use Copy Last Transcript." }
        // AXSelectedText writes can report success without producing editor
        // input events (notably in web/Electron editors). Use the normal Paste
        // command so the target app handles text through its regular input path.
        // Restore every clipboard type unless the user copies something meanwhile.
        let clipboard = NSPasteboard.general
        let saved: [[NSPasteboard.PasteboardType: Data]] = (clipboard.pasteboardItems ?? []).map { item in
            var data: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types { if let value = item.data(forType: type) { data[type] = value } }
            return data
        }
        guard stillFocused(target),
              let down = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: false) else {
            log("focus_or_event_unavailable", dictation: dictation)
            return "Could not insert; use Copy Last Transcript."
        }
        clipboard.clearContents()
        clipboard.setString(text, forType: .string)
        let revision = clipboard.changeCount
        down.flags = .maskCommand
        up.flags = .maskCommand
        guard stillFocused(target) else {
            log("focus_changed", dictation: dictation)
            restoreClipboard(saved, ifUnchanged: revision)
            return "Input focus changed; use Copy Last Transcript."
        }
        log("paste_dispatched", dictation: dictation)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        try? await Task.sleep(for: .milliseconds(350))
        restoreClipboard(saved, ifUnchanged: revision)
        return nil
    }

    private static func log(_ outcome: String, dictation: Int?) {
        Diagnostics.shared.record("insertion.result", category: "Insertion", dictation: dictation, detail: true, fields: ["outcome": outcome])
    }

    private static func restoreClipboard(_ saved: [[NSPasteboard.PasteboardType: Data]], ifUnchanged revision: Int) {
        let clipboard = NSPasteboard.general
        guard clipboard.changeCount == revision else { return }
        clipboard.clearContents()
        let items = saved.map { values in
            let item = NSPasteboardItem()
            for (type, data) in values { item.setData(data, forType: type) }
            return item
        }
        if !items.isEmpty { clipboard.writeObjects(items) }
    }
}
