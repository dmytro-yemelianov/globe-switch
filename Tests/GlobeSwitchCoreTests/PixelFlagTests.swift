@testable import GlobeSwitchCore
import Testing

@Suite struct PixelFlagTests {
    @Test func everyFlagFillsTheGridWithKnownColours() {
        for (region, flag) in PixelFlag.byRegion {
            #expect(flagEmoji(region: region) != nil, "\(region) is not a region with a flag")
            #expect(flag.rows.count == PixelFlag.height, "\(region)")
            for row in flag.rows {
                #expect(row.count == PixelFlag.width, "\(region): \(row)")
                #expect(row.allSatisfy { flag.colors[$0] != nil }, "\(region): \(row)")
            }
        }
    }

    @Test func givesOpaqueRGBATopRowFirst() {
        let ukraine = PixelFlag.byRegion["UA"]!.rgba
        #expect(ukraine.count == PixelFlag.width * PixelFlag.height * 4)
        #expect(Array(ukraine.prefix(4)) == [0x00, 0x57, 0xB7, 0xFF])
        #expect(Array(ukraine.suffix(4)) == [0xFF, 0xD7, 0x00, 0xFF])
    }

    @Test func theUnionJackLooksTheSameUpsideDown() {
        let rows = PixelFlag.byRegion["GB"]!.rows
        #expect(rows.reversed().map { String($0.reversed()) } == rows)
    }
}
