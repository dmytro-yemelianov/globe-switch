@testable import GlobeSwitchCore
import Foundation
import Testing

@Suite struct PixelFlagTests {
    @Test func everyFlagFillsTheGridWithKnownColours() throws {
        #expect(Set(PixelFlag.regions).count == PixelFlag.regions.count, "a region is drawn twice")
        for region in PixelFlag.regions {
            let flag = try #require(PixelFlag(region: region), "\(region) doesn't parse")
            #expect(flag.rows.count == PixelFlag.height, "\(region)")
            for row in flag.rows {
                #expect(row.count == PixelFlag.width, "\(region): \(row)")
                #expect(row.allSatisfy { $0 == "." || flag.colors[$0] != nil }, "\(region): \(row)")
            }
            for letter in flag.colors.keys {
                #expect(flag.rows.contains { $0.contains(letter) }, "\(region): colour \(letter) is unused")
            }
        }
    }

    /// Two regions have no flag of their own: Eurozone and Outlying Oceania.
    @Test func drawsEveryRegionWithAFlag() {
        let flagless: Set = ["EZ", "QO"]
        let missing = Locale.Region.isoRegions.map(\.identifier)
            .filter { flagEmoji(region: $0) != nil && !flagless.contains($0) && PixelFlag(region: $0) == nil }
        #expect(missing.isEmpty, "no pixel flag for \(missing.sorted())")
    }

    @Test func onlyNepalIsNotRectangular() {
        let shaped = PixelFlag.regions.filter { PixelFlag(region: $0)?.rows.contains { $0.contains(".") } ?? false }
        #expect(shaped == ["NP"])
    }

    @Test func regionsWithoutTheirOwnFlagFlyAnothers() {
        #expect(PixelFlag(region: "BV") == PixelFlag(region: "NO"))
        #expect(PixelFlag(region: "UM") == PixelFlag(region: "US"))
        #expect(PixelFlag(region: "ua") == PixelFlag(region: "UA"))
        #expect(PixelFlag(region: "ZZ") == nil)
    }

    @Test func givesRGBATopRowFirst() throws {
        let ukraine = try #require(PixelFlag(region: "UA")).rgba
        #expect(ukraine.count == PixelFlag.width * PixelFlag.height * 4)
        #expect(Array(ukraine.prefix(4)) == [0x00, 0x57, 0xB7, 0xFF])
        #expect(Array(ukraine.suffix(4)) == [0xFF, 0xD7, 0x00, 0xFF])
        let nepal = try #require(PixelFlag(region: "NP")).rgba
        #expect(Array(nepal.suffix(4)) == [0, 0, 0, 0])
    }

    @Test func theUnionJackLooksTheSameUpsideDown() throws {
        let rows = try #require(PixelFlag(region: "GB")).rows
        #expect(rows.reversed().map { String($0.reversed()) } == rows)
    }
}
