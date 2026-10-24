/// User settings, stored in the `dev.yemelianov.globe-switch` preferences domain:
///
///     defaults write dev.yemelianov.globe-switch TapWindowMilliseconds -int 400
///     defaults write dev.yemelianov.globe-switch SkippedLayouts -array com.apple.keylayout.Russian
///     defaults write dev.yemelianov.globe-switch CycleOrder -string recent
///     defaults write dev.yemelianov.globe-switch ShowIndicator -bool false
///     defaults write dev.yemelianov.globe-switch LayoutFlags -dict com.apple.keylayout.ABC GB
///     defaults write dev.yemelianov.globe-switch Sound -string Pop
///     defaults write dev.yemelianov.globe-switch SoundVolume -float 0.2
///
/// The agent rereads them on every 🌐 press, so changes apply without a restart.
public struct Settings: Equatable {
    public static let keys = [
        "TapWindowMilliseconds", "SkippedLayouts", "CycleOrder", "ShowIndicator", "LayoutFlags", "PlaySound", "Sound",
        "SoundVolume",
    ]
    public static let tapWindowRange = 100...2000

    /// 🌐 released within this many milliseconds, with nothing else pressed, counts as a tap.
    public var tapWindowMilliseconds = 600
    /// Input source IDs a tap never switches to, as printed by `globe-switch --list`.
    public var skippedLayouts: Set<String> = []
    public var cycleOrder = CycleOrder.list
    /// Show the new layout's flag and name for a moment after each switch.
    public var showIndicator = true
    /// Flags chosen per input source ID: a region code such as "GB", or any text to show instead.
    public var layoutFlags: [String: String] = [:]
    /// Play a short sound after each switch.
    public var playSound = true
    /// GlobeSwitch's own soft click, or a sound from /System/Library/Sounds (Tink, Pop, …) or ~/Library/Sounds.
    public var sound = "Click"
    /// Relative to the system volume, from 0 to 1.
    public var soundVolume = 0.35

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
        if let flags = values["LayoutFlags"] as? [String: String] {
            layoutFlags = flags
        }
        if let play = values["PlaySound"] as? Bool {
            playSound = play
        }
        if let name = values["Sound"] as? String, !name.isEmpty {
            sound = name
        }
        if let volume = values["SoundVolume"] as? Double {
            soundVolume = min(max(volume, 0), 1)
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
        if !layoutFlags.isEmpty {
            changes.append("LayoutFlags=" + layoutFlags.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" }.joined(separator: ","))
        }
        if playSound != defaults.playSound { changes.append("PlaySound=\(playSound)") }
        if sound != defaults.sound { changes.append("Sound=\(sound)") }
        if soundVolume != defaults.soundVolume { changes.append("SoundVolume=\(soundVolume)") }
        return changes
    }
}
