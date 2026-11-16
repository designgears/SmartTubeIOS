import Foundation
import Testing

@testable import SmartTubeIOSCore

// MARK: - GlassStyleSettingTests

@Suite("AppSettings.glassStyle")
struct GlassStyleSettingTests {

    @Test func defaultsToStandard() {
        #expect(AppSettings().glassStyle == .standard)
    }

    @Test func roundTripPreservesValue() throws {
        var original = AppSettings()
        original.glassStyle = .frosted

        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(original))

        #expect(decoded.glassStyle == .frosted)
    }

    @Test func oldJSONWithoutTheFieldDecodesToTheDefault() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(settings.glassStyle == .standard)
    }

    /// The old "Disable Liquid Glass" switch, when on, carries over as Solid.
    @Test func oldDisableSwitchBecomesSolid() throws {
        let on = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"disableLiquidGlass":true}"#.utf8))
        let off = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"disableLiquidGlass":false}"#.utf8))
        #expect(on.glassStyle == .solid)
        #expect(off.glassStyle == .standard)
    }

    @Test func newValueWinsOverTheOldSwitch() throws {
        let json = Data(#"{"disableLiquidGlass":true,"glassStyle":"frosted"}"#.utf8)
        #expect(try JSONDecoder().decode(AppSettings.self, from: json).glassStyle == .frosted)
    }
}
