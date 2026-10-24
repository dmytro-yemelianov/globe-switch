/// User settings, stored in the `dev.yemelianov.globe-switch` preferences domain:
///
///     defaults write dev.yemelianov.globe-switch TapWindowMilliseconds -int 400
///     defaults write dev.yemelianov.globe-switch SkippedLayouts -array com.apple.keylayout.Russian
///     defaults write dev.yemelianov.globe-switch CycleOrder -string recent
///     defaults write dev.yemelianov.globe-switch ShowIndicator -bool true
///
/// The agent rereads them on every 🌐 press, so changes apply without a restart.
public struct Settings: Equatable {
    public static let keys = ["TapWindowMilliseconds", "SkippedLayouts", "CycleOrder", "ShowIndicator"]
    public static let tapWindowRange = 100...2000

    /// 🌐 released within this many milliseconds, with nothing else pressed, counts as a tap.
    public var tapWindowMilliseconds = 600
    /// Input source IDs a tap never switches to, as printed by `globe-switch --list`.
    public var skippedLayouts: Set<String> = []
    public var cycleOrder = CycleOrder.list
    /// Show the new layout's name for a moment after each switch.
    public var showIndicator = false

    public init() {}

    /// Settings from raw preference values. Values of the wrong type are ignored, and the tap
    /// window is clamped to `tapWindowRange`.
    public init(values: [String: Any]) {
        if let window = values["TapWindowMilliseconds"] as? Int {
            tapWindowMilliseconds = min(max(window, Self.tapWindowRange.lowerBound), Self.tapWindowRange.upperBound)
        }
        if let skipped = values["SkippedLayouts"] as? [String] {
            skippedLayouts = Set(skipped)
        }
        if let order = (values["CycleOrder"] as? String).flatMap(CycleOrder.init(rawValue:)) {
            cycleOrder = order
        }
        if let show = values["ShowIndicator"] as? Bool {
            showIndicator = show
        }
    }

    public var tapWindowNanos: UInt64 { UInt64(tapWindowMilliseconds) * 1_000_000 }

    /// The settings that differ from the defaults, for `globe-switch doctor`.
    public var changes: [String] {
        let defaults = Settings()
        var changes: [String] = []
        if tapWindowMilliseconds != defaults.tapWindowMilliseconds {
            changes.append("TapWindowMilliseconds=\(tapWindowMilliseconds)")
        }
        if !skippedLayouts.isEmpty { changes.append("SkippedLayouts=\(skippedLayouts.sorted().joined(separator: ","))") }
        if cycleOrder != defaults.cycleOrder { changes.append("CycleOrder=\(cycleOrder.rawValue)") }
        if showIndicator != defaults.showIndicator { changes.append("ShowIndicator=\(showIndicator)") }
        return changes
    }
}
