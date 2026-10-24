/// Decides whether a press of fn (🌐) was a clean tap: released within `maxTapNanos`, with no
/// other key, modifier, media key, click or scroll while it was held. Anything else is left to
/// macOS, so fn+arrows, fn+E and fn+F-keys keep working.
public struct TapDetector {
    public enum Event: Equatable {
        case fnDown(at: UInt64)
        case fnUp(at: UInt64)
        /// Any other key, modifier, media key, click or scroll.
        case other
    }

    public enum Outcome: Equatable {
        case none
        case tap
        case heldTooLong(nanos: UInt64)
    }

    public var maxTapNanos: UInt64
    private var downAt: UInt64?
    private var chorded = false

    public init(maxTapNanos: UInt64 = 600_000_000) {
        self.maxTapNanos = maxTapNanos
    }

    public mutating func handle(_ event: Event) -> Outcome {
        switch event {
        case .fnDown(let time):
            downAt = time
            chorded = false
            return .none
        case .other:
            if downAt != nil { chorded = true }
            return .none
        case .fnUp(let time):
            guard let start = downAt else { return .none }
            downAt = nil
            if chorded { return .none }
            let held = time >= start ? time - start : 0
            return held <= maxTapNanos ? .tap : .heldTooLong(nanos: held)
        }
    }

    /// Forgets a press in progress, e.g. after the event tap was off and may have missed a chord.
    public mutating func reset() {
        downAt = nil
        chorded = false
    }
}
