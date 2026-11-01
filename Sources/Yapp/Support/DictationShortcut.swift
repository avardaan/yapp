import CoreGraphics

enum DictationShortcut: String, CaseIterable, Identifiable {
    case fn, rightOption, rightControl
    var id: String { rawValue }
    var title: String {
        switch self {
        case .fn: return "Fn"
        case .rightOption: return "Right Option"
        case .rightControl: return "Right Control"
        }
    }
    var keyCode: Int64 {
        switch self {
        case .fn: return 63
        case .rightOption: return 61
        case .rightControl: return 62
        }
    }
    var flag: CGEventFlags {
        switch self {
        case .fn: return .maskSecondaryFn
        case .rightOption: return .maskAlternate
        case .rightControl: return .maskControl
        }
    }
}
