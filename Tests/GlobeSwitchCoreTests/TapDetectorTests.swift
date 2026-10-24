import GlobeSwitchCore
import Testing

private let ms: UInt64 = 1_000_000

@Suite struct TapDetectorTests {
    @Test func quickReleaseIsATap() {
        var detector = TapDetector()
        #expect(detector.handle(.fnDown(at: 0)) == .none)
        #expect(detector.handle(.fnUp(at: 120 * ms)) == .tap)
    }

    @Test func releaseExactlyAtTheLimitIsStillATap() {
        var detector = TapDetector(maxTapNanos: 600 * ms)
        _ = detector.handle(.fnDown(at: 0))
        #expect(detector.handle(.fnUp(at: 600 * ms)) == .tap)
    }

    @Test func longHoldIsNotATap() {
        var detector = TapDetector(maxTapNanos: 600 * ms)
        _ = detector.handle(.fnDown(at: 1_000 * ms))
        #expect(detector.handle(.fnUp(at: 1_900 * ms)) == .heldTooLong(nanos: 900 * ms))
    }

    @Test func anythingElseWhileHeldMakesAChord() {
        var detector = TapDetector()
        _ = detector.handle(.fnDown(at: 0))
        _ = detector.handle(.other) // fn+←, fn+E, a click, a scroll, …
        #expect(detector.handle(.fnUp(at: 100 * ms)) == .none)
    }

    @Test func chordedLongHoldIsNotReported() {
        var detector = TapDetector(maxTapNanos: 600 * ms)
        _ = detector.handle(.fnDown(at: 0))
        _ = detector.handle(.other)
        #expect(detector.handle(.fnUp(at: 2_000 * ms)) == .none)
    }

    @Test func eventsBeforeThePressDoNotCount() {
        var detector = TapDetector()
        _ = detector.handle(.other)
        _ = detector.handle(.fnDown(at: 0))
        #expect(detector.handle(.fnUp(at: 50 * ms)) == .tap)
    }

    @Test func aChordDoesNotSpoilTheNextTap() {
        var detector = TapDetector()
        _ = detector.handle(.fnDown(at: 0))
        _ = detector.handle(.other)
        _ = detector.handle(.fnUp(at: 100 * ms))
        _ = detector.handle(.fnDown(at: 500 * ms))
        #expect(detector.handle(.fnUp(at: 600 * ms)) == .tap)
    }

    @Test func releaseWithoutAPressIsIgnored() {
        var detector = TapDetector()
        #expect(detector.handle(.fnUp(at: 100 * ms)) == .none)
        _ = detector.handle(.fnDown(at: 200 * ms))
        _ = detector.handle(.fnUp(at: 300 * ms))
        #expect(detector.handle(.fnUp(at: 400 * ms)) == .none)
    }

    @Test func aRepeatedPressRestartsTheClock() {
        var detector = TapDetector(maxTapNanos: 600 * ms)
        _ = detector.handle(.fnDown(at: 0))
        _ = detector.handle(.fnDown(at: 1_000 * ms)) // the release in between was missed
        #expect(detector.handle(.fnUp(at: 1_100 * ms)) == .tap)
    }

    @Test func resetDropsThePressInProgress() {
        var detector = TapDetector()
        _ = detector.handle(.fnDown(at: 0))
        detector.reset()
        #expect(detector.handle(.fnUp(at: 100 * ms)) == .none)
    }

    @Test func clockGoingBackwardsCountsAsZeroHold() {
        var detector = TapDetector()
        _ = detector.handle(.fnDown(at: 500 * ms))
        #expect(detector.handle(.fnUp(at: 400 * ms)) == .tap)
    }
}

@Suite struct LayoutCycleTests {
    @Test func movesToTheNextLayoutAndWraps() {
        #expect(nextLayoutIndex(after: 0, count: 2) == 1)
        #expect(nextLayoutIndex(after: 1, count: 2) == 0)
        #expect(nextLayoutIndex(after: 1, count: 3) == 2)
        #expect(nextLayoutIndex(after: 2, count: 3) == 0)
    }

    @Test func unknownCurrentLayoutStartsAtTheFirst() {
        #expect(nextLayoutIndex(after: nil, count: 3) == 0)
        #expect(nextLayoutIndex(after: 7, count: 3) == 0)
        #expect(nextLayoutIndex(after: -1, count: 3) == 0)
    }

    @Test func nothingToSwitchToWithFewerThanTwoLayouts() {
        #expect(nextLayoutIndex(after: 0, count: 1) == nil)
        #expect(nextLayoutIndex(after: nil, count: 0) == nil)
    }
}

@Suite struct FnUsageTests {
    @Test func describesKnownMissingAndUnknownValues() {
        #expect(FnUsage.describe(0) == "Do Nothing")
        #expect(FnUsage.describe(1) == "Change Input Source")
        #expect(FnUsage.describe(nil) == "not set (macOS default)")
        #expect(FnUsage.describe(9) == "unknown value 9")
    }
}
