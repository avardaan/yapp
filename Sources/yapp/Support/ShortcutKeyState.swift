// Only the selected physical modifier starts dictation. A chord cancels
// until that key is released again; unrelated keys never start recording.
struct ShortcutKeyState {
    enum Action: Equatable { case pressed, released, cancelled }
    private(set) var held = false
    private var chord = false

    mutating func flagsChanged(keyCode: Int64, isDown: Bool, triggerKeyCode: Int64 = 63) -> Action? {
        guard keyCode == triggerKeyCode else { return nil }
        if isDown {
            guard !held else { return nil }
            held = true
            chord = false
            return .pressed
        }
        guard held else { return nil }
        held = false
        let wasChord = chord
        chord = false
        return wasChord ? nil : .released
    }

    mutating func otherKeyPressed() -> Action? {
        guard held, !chord else { return nil }
        chord = true
        return .cancelled
    }

    mutating func reset() -> Action? {
        let wasHeld = held
        held = false
        chord = false
        return wasHeld ? .cancelled : nil
    }
}
