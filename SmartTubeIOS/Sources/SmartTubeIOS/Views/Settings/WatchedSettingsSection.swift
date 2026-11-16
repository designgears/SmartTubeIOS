import SmartTubeIOSCore
import SwiftUI

// MARK: - Watched Videos

/// What happens to videos you've already seen — here or, optionally, on YouTube.
struct WatchedSettingsSection: View {
    @Environment(SettingsStore.self) private var store

    var body: some View {
        @Bindable var store = store
        Section {
            Toggle("Dim Watched Videos", isOn: $store.settings.dimWatchedVideos)
                .accessibilityIdentifier(AccessibilityID.Settings.dimWatchedToggle)
            Toggle("Hide in Feeds", isOn: $store.settings.hideWatchedInFeeds)
                .accessibilityIdentifier(AccessibilityID.Settings.hideWatchedInFeedsToggle)
            Toggle("Skip When Playing Next", isOn: $store.settings.skipWatchedWhenPlayingNext)
                .accessibilityIdentifier(AccessibilityID.Settings.skipWatchedToggle)
            threshold
            Toggle("Use YouTube Watch History", isOn: $store.settings.watchedUsesYouTubeHistory)
                .accessibilityIdentifier(AccessibilityID.Settings.watchedUsesYouTubeHistoryToggle)
            Toggle("Include Music", isOn: $store.settings.watchedIncludesMusic)
                .accessibilityIdentifier(AccessibilityID.Settings.watchedIncludesMusicToggle)
        } header: {
            Text("Watched Videos")
        } footer: {
            Text(
                "Hide in Feeds covers Home, Subscriptions and Explore. Skip When Playing Next covers autoplay, "
                    + "Next, queues and playlists. History and Continue Watching are left as they are, and music "
                    + "is never dimmed or skipped unless Include Music is on.")
        }
    }

    /// How much of a video has to have been seen.
    @ViewBuilder private var threshold: some View {
        @Bindable var store = store
        let label = "Counts as Watched At"
        let percents = Array(stride(from: 50, through: 100, by: 5)).map { Double($0) / 100 }
        TVPickerRow(
            label, value: Self.percent(store.settings.hideWatchedThreshold),
            choices: tvChoices($store.settings.hideWatchedThreshold, percents) { Self.percent($0) }
        ) {
            Picker(label, selection: $store.settings.hideWatchedThreshold) {
                ForEach(percents, id: \.self) { Text(Self.percent($0)).tag($0) }
            }
        }
        .accessibilityIdentifier(AccessibilityID.Settings.watchedThresholdRow)
    }

    private static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }
}
