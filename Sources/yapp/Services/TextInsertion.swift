import AppKit
import ApplicationServices

@MainActor
final class TextInsertion {
    struct Target {
        let processID: pid_t
        let element: AXUIElement
        var app = "unknown"
        var role = "unknown"
        /// Controlled metadata for diagnostics: the target app's bundle ID and AX role, never content.
        var fields: [String: String] { ["target_app": app, "target_role": role] }
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
        var role: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        return Target(processID: app.processIdentifier, element: element, app: app.bundleIdentifier ?? "unknown",
                      role: [role as? String, subrole as? String].compactMap { $0 }.joined(separator: "/"))
    }

    static func stillFocused(_ target: Target) -> Bool {
        guard let current = captureTarget() else { return false }
        return current.processID == target.processID && CFEqual(current.element, target.element)
    }

    // Return nil after sending Paste, or an explanatory status if insertion is unsafe or unavailable.
    // Never paste into a field/app the user switched to during transcription.
    static func insert(_ text: String, into target: Target?, dictation: UUID? = nil) async -> String? {
        let text = DictationText.clean(text)
        func log(_ outcome: String, _ extra: [String: String] = [:]) {
            Self.log(outcome, dictation: dictation, fields: (target?.fields ?? [:]).merging(["chars": String(text.count)]) { $1 }.merging(extra) { $1 })
        }
        guard !text.isEmpty else { log("empty_text"); return "No speech detected" }
        guard allowed else { log("accessibility_missing"); return "Enable Accessibility to insert; transcript available in Copy Last Transcript." }
        guard let target, stillFocused(target) else { log(target == nil ? "no_safe_target" : "focus_changed"); return "Input focus changed; use Copy Last Transcript." }
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
            log("focus_or_event_unavailable")
            return "Could not insert; use Copy Last Transcript."
        }
        clipboard.clearContents()
        clipboard.setString(text, forType: .string)
        let revision = clipboard.changeCount
        down.flags = .maskCommand
        up.flags = .maskCommand
        guard stillFocused(target) else {
            log("focus_changed", ["clipboard": restoreClipboard(saved, ifUnchanged: revision)])
            return "Input focus changed; use Copy Last Transcript."
        }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        try? await Task.sleep(for: .milliseconds(350))
        // Focus after paste distinguishes "app swallowed/duplicated it" from "focus moved away".
        log("paste_dispatched", ["clipboard": restoreClipboard(saved, ifUnchanged: revision),
                                 "focus_after": String(stillFocused(target))])
        return nil
    }

    private static func log(_ outcome: String, dictation: UUID?, fields: [String: String]) {
        Diagnostics.shared.record("insertion.result", category: "Insertion", dictation: dictation, fields: fields.merging(["outcome": outcome]) { $1 })
    }

    /// Returns a diagnostics label: restored, changed_meanwhile (left alone), or was_empty.
    private static func restoreClipboard(_ saved: [[NSPasteboard.PasteboardType: Data]], ifUnchanged revision: Int) -> String {
        let clipboard = NSPasteboard.general
        guard clipboard.changeCount == revision else { return "changed_meanwhile" }
        clipboard.clearContents()
        let items = saved.map { values in
            let item = NSPasteboardItem()
            for (type, data) in values { item.setData(data, forType: type) }
            return item
        }
        if !items.isEmpty { clipboard.writeObjects(items) }
        return items.isEmpty ? "was_empty" : "restored"
    }
}
