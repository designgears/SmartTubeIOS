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

    private static func mark(_ choice: AppSettings.AccentColorChoice?) -> Color {
        choice?.color ?? AppSettings.defaultMarkColor.color ?? .blue
    }
}
