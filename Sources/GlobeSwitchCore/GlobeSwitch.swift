public enum GlobeSwitch {
    public static let version = "0.2.0"
    /// LaunchAgent label, code-signing identifier and unified-log subsystem.
    public static let label = "dev.yemelianov.globe-switch"
}

/// Index of the layout a tap switches to: the one after `current`, wrapping around, or the first
/// one when the current layout is not in the list. Nil when there is nothing to switch to.
public func nextLayoutIndex(after current: Int?, count: Int) -> Int? {
    guard count > 1 else { return nil }
    guard let current, current >= 0, current < count else { return 0 }
    return (current + 1) % count
}
