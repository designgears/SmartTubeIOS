import SmartTubeIOSCore
import SwiftUI

// MARK: - App colors

/// The app's mark colors: the services' LIVE colors, and the watched bar picked in Settings ›
/// Colors (views outside the settings environment, and any `.system` choice, get
/// `AppSettings.defaultMarkColor`).
@MainActor
enum AppColor {
    /// LIVE badges, rings and tags — the app's own and the player's (see `TVLiveBadgeTint`) — in
    /// the service's own LIVE color: YouTube's red, Twitch's red, Kick's green.
    static func live(_ platform: StreamPlatform = .youtube) -> Color {
        switch platform {
        case .youtube: Color(red: 0xFF / 255, green: 0, blue: 0)
        case .twitch: Color(red: 0xEB / 255, green: 0x04 / 255, blue: 0)
        case .kick: Color(red: 0x53 / 255, green: 0xFC / 255, blue: 0x18 / 255)
        }
    }

    /// Text on a `live` badge: Kick's green is light.
    static func onLive(_ platform: StreamPlatform = .youtube) -> Color {
        platform == .kick ? .black : .white
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
