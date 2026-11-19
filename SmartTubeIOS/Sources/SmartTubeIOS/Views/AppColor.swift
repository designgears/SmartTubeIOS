import SmartTubeIOSCore
import SwiftUI

// MARK: - App colors

/// The colors picked in Settings › Colors. Views outside the settings environment (and any
/// `.system` choice) get `AppSettings.defaultMarkColor`.
@MainActor
enum AppColor {
    /// LIVE badges, rings and tags — the app's own and the player's (see `TVLiveBadgeTint`).
    static func live(_ store: SettingsStore?) -> Color {
        mark(store?.settings.liveColor)
    }

    /// The bar on a card showing how much has been watched.
    static func watched(_ store: SettingsStore?) -> Color {
        mark(store?.settings.watchedBarColor)
    }

    /// Twitch's purple and Kick's green, for their badges.
    static func platform(_ platform: StreamPlatform) -> Color {
        switch platform {
        case .twitch: Color(red: 0x91 / 255, green: 0x46 / 255, blue: 0xFF / 255)
        case .kick: Color(red: 0x53 / 255, green: 0xFC / 255, blue: 0x18 / 255)
        case .youtube: .red
        }
    }

    /// Text on a `platform` badge: Kick's green is light.
    static func onPlatform(_ platform: StreamPlatform) -> Color {
        platform == .kick ? .black : .white
    }

    private static func mark(_ choice: AppSettings.AccentColorChoice?) -> Color {
        choice?.color ?? AppSettings.defaultMarkColor.color ?? .blue
    }
}
