import GlobeSwitchCore
import Testing

private let abc = "com.apple.keylayout.ABC"
private let ukr = "com.apple.keylayout.Ukrainian-PC"
private let ger = "com.apple.keylayout.German"
private let rus = "com.apple.keylayout.Russian"

@Suite struct ListOrderTests {
    @Test func movesToTheNextLayoutAndWraps() {
        #expect(nextLayout(current: abc, enabled: [abc, ukr]) == ukr)
        #expect(nextLayout(current: ukr, enabled: [abc, ukr]) == abc)
        #expect(nextLayout(current: ukr, enabled: [abc, ukr, ger]) == ger)
        #expect(nextLayout(current: ger, enabled: [abc, ukr, ger]) == abc)
    }

    @Test func unknownCurrentLayoutStartsAtTheFirst() {
        #expect(nextLayout(current: nil, enabled: [abc, ukr, ger]) == abc)
        #expect(nextLayout(current: rus, enabled: [abc, ukr, ger]) == abc)
    }

    @Test func nothingToSwitchToWithFewerThanTwoLayouts() {
        #expect(nextLayout(current: abc, enabled: [abc]) == nil)
        #expect(nextLayout(current: nil, enabled: []) == nil)
    }

    @Test func skippedLayoutsArePassedOver() {
        #expect(nextLayout(current: abc, enabled: [abc, rus, ukr], skipped: [rus]) == ukr)
        #expect(nextLayout(current: ukr, enabled: [abc, rus, ukr], skipped: [rus]) == abc)
    }

    @Test func fromASkippedLayoutItMovesForward() {
        // Selected from the menu bar, then 🌐: carry on from its place, not from the start.
        #expect(nextLayout(current: rus, enabled: [abc, rus, ukr, ger], skipped: [rus]) == ukr)
        // The only other layout is still reachable.
        #expect(nextLayout(current: rus, enabled: [abc, rus], skipped: [rus]) == abc)
    }

    @Test func skippingEverythingElseLeavesNothing() {
        #expect(nextLayout(current: abc, enabled: [abc, rus], skipped: [rus]) == nil)
        #expect(nextLayout(current: abc, enabled: [abc, rus], skipped: [abc, rus]) == nil)
    }
}

@Suite struct RecentOrderTests {
    @Test func goesBackToTheMostRecentOtherLayout() {
        let recent = [ger, abc, ukr]
        #expect(nextLayout(current: ger, enabled: [abc, ukr, ger], recent: recent, order: .recent) == abc)
    }

    @Test func togglesBetweenTheLastTwo() {
        // After ABC → German, a tap goes back to ABC, and the next one to German again.
        #expect(nextLayout(current: abc, enabled: [abc, ukr, ger], recent: [abc, ger, ukr], order: .recent) == ger)
    }

    @Test func ignoresRecentLayoutsThatAreSkippedOrGone() {
        let enabled = [abc, ukr, ger]
        #expect(nextLayout(current: ger, enabled: enabled, skipped: [abc], recent: [ger, abc, ukr], order: .recent) == ukr)
        #expect(nextLayout(current: ger, enabled: enabled, recent: [ger, rus, ukr], order: .recent) == ukr)
    }

    @Test func withoutHistoryFallsBackToListOrder() {
        #expect(nextLayout(current: ukr, enabled: [abc, ukr, ger], recent: [ukr], order: .recent) == ger)
        #expect(nextLayout(current: ukr, enabled: [abc, ukr, ger], order: .recent) == ger)
    }
}

@Suite struct SettingsTests {
    @Test func defaultsWhenNothingIsSet() {
        let settings = Settings(values: [:])
        #expect(settings == Settings())
        #expect(settings.tapWindowMilliseconds == 600)
        #expect(settings.cycleOrder == .list)
        #expect(!settings.showIndicator)
        #expect(settings.changes.isEmpty)
    }

    @Test func readsEveryKey() {
        let settings = Settings(values: [
            "TapWindowMilliseconds": 400,
            "SkippedLayouts": [rus],
            "CycleOrder": "recent",
            "ShowIndicator": true,
        ])
        #expect(settings.tapWindowMilliseconds == 400)
        #expect(settings.tapWindowNanos == 400_000_000)
        #expect(settings.skippedLayouts == [rus])
        #expect(settings.cycleOrder == .recent)
        #expect(settings.showIndicator)
        #expect(settings.changes == [
            "TapWindowMilliseconds=400", "SkippedLayouts=\(rus)", "CycleOrder=recent", "ShowIndicator=true",
        ])
    }

    @Test func clampsTheTapWindow() {
        #expect(Settings(values: ["TapWindowMilliseconds": 5]).tapWindowMilliseconds == 100)
        #expect(Settings(values: ["TapWindowMilliseconds": 60_000]).tapWindowMilliseconds == 2000)
    }

    @Test func ignoresMalformedValues() {
        let settings = Settings(values: [
            "TapWindowMilliseconds": "fast",
            "SkippedLayouts": rus,
            "CycleOrder": "random",
            "ShowIndicator": "yes",
        ])
        #expect(settings == Settings())
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
