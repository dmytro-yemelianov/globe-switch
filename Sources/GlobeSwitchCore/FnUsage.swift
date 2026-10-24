/// System Settings → Keyboard → "Press 🌐 key to", stored as `com.apple.HIToolbox AppleFnUsageType`.
/// globe-switch needs Do Nothing; with anything else macOS reacts to the same tap.
public enum FnUsage: Int, CaseIterable {
    case doNothing = 0
    case changeInputSource = 1
    case showEmojiAndSymbols = 2
    case startDictation = 3

    public var title: String {
        switch self {
        case .doNothing: return "Do Nothing"
        case .changeInputSource: return "Change Input Source"
        case .showEmojiAndSymbols: return "Show Emoji & Symbols"
        case .startDictation: return "Start Dictation"
        }
    }

    /// A raw setting value for display, including a missing one and values this version doesn't know.
    public static func describe(_ rawValue: Int?) -> String {
        guard let rawValue else { return "not set (macOS default)" }
        return FnUsage(rawValue: rawValue)?.title ?? "unknown value \(rawValue)"
    }
}
