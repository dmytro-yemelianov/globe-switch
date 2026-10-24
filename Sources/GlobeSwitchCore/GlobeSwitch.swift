public enum GlobeSwitch {
    public static let version = "0.5.0"
    /// Bundle identifier, LaunchAgent label, preferences domain and unified-log subsystem.
    public static let label = "dev.yemelianov.globe-switch"
}

/// How a tap picks the next layout.
public enum CycleOrder: String, CaseIterable {
    /// The next enabled layout in system order.
    case list
    /// Back to the most recently used other layout, like a quick Ctrl+Space.
    case recent
}

/// The layout a tap switches to, or nil when there is nothing to switch to.
/// - Parameters:
///   - enabled: selectable layouts in system order.
///   - skipped: layouts the user excluded from switching.
///   - recent: layouts in the order they were last used, most recent first.
public func nextLayout(current: String?, enabled: [String], skipped: Set<String> = [],
                       recent: [String] = [], order: CycleOrder = .list) -> String? {
    let others = enabled.filter { $0 != current && !skipped.contains($0) }
    guard !others.isEmpty else { return nil }
    if order == .recent, let back = recent.first(where: others.contains) {
        return back
    }
    // Walk on from the current layout's place in the full list, so a skipped or unknown current
    // layout still moves forward instead of jumping back to the start.
    let start = current.flatMap { enabled.firstIndex(of: $0) } ?? -1
    for offset in 1...enabled.count {
        let candidate = enabled[(start + offset) % enabled.count]
        if others.contains(candidate) { return candidate }
    }
    return others[0]
}

/// The layouts the indicator lines up, in system order: those a tap can reach, plus `keeping`
/// (the layouts switched from and to) even when they are skipped.
public func indicatorLayouts(enabled: [String], skipped: Set<String> = [], keeping: Set<String> = []) -> [String] {
    enabled.filter { !skipped.contains($0) || keeping.contains($0) }
}
