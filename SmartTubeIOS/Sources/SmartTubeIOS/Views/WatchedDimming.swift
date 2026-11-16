import SmartTubeIOSCore
import SwiftUI

// MARK: - Dimming watched videos

extension EnvironmentValues {
    /// Off where every video is watched by definition (History, Continue Watching).
    @Entry var dimsWatchedVideos = true
}

extension View {
    /// Fades `video`'s card when it's been watched (Settings › Watched Videos › Dim), back to
    /// full strength while it has focus. `settings` stands in where there's no `SettingsStore`
    /// in the environment (e.g. the player's panels).
    func dimmedIfWatched(_ video: Video, settings: AppSettings? = nil) -> some View {
        modifier(WatchedDimming(video: video, explicitSettings: settings))
    }
}

private struct WatchedDimming: ViewModifier {
    let video: Video
    let explicitSettings: AppSettings?

    /// Optional: a card shown outside the settings environment just isn't dimmed.
    @Environment(SettingsStore.self) private var store: SettingsStore?
    @Environment(\.dimsWatchedVideos) private var enabled
    @Environment(\.isFocused) private var isFocused

    func body(content: Content) -> some View {
        content
            .opacity(isDimmed && !isFocused ? 0.45 : 1)
            .animation(.easeOut(duration: 0.2), value: isFocused)
    }

    private var isDimmed: Bool {
        guard enabled, let settings = explicitSettings ?? store?.settings, settings.dimWatchedVideos else {
            return false
        }
        return WatchedStore.shared.isWatched(video, policy: settings.watchedPolicy)
    }
}
