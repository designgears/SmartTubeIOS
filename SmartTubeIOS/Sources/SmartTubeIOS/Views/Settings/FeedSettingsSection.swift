import SmartTubeIOSCore
import SwiftUI

// MARK: - Feeds

/// What shows up in Home and the other feeds.
struct FeedSettingsSection: View {
    @Environment(SettingsStore.self) private var store

    var body: some View {
        @Bindable var store = store
        Section {
            #if os(tvOS)
            Toggle("Featured Banner on Home", isOn: $store.settings.showHomeHero)
                .accessibilityIdentifier(AccessibilityID.Settings.showHomeHeroToggle)
            #endif
            Toggle("Hide Shorts", isOn: $store.settings.hideShorts)
                .accessibilityIdentifier(AccessibilityID.Settings.hideShortsToggle)
            #if !os(tvOS)
            // The tvOS shelves don't apply these filters.
            Toggle("Hide Live Shorts", isOn: $store.settings.hideLiveShorts)
                .accessibilityIdentifier(AccessibilityID.Settings.hideLiveShortsToggle)
            Toggle("Hide Premieres", isOn: $store.settings.hideVideoPremieres)
                .accessibilityIdentifier(AccessibilityID.Settings.hideVideoPremieresToggle)
            Toggle("Hide Watched Videos", isOn: $store.settings.hideWatchedVideos)
                .accessibilityIdentifier(AccessibilityID.Settings.hideWatchedVideosToggle)
            if store.settings.hideWatchedVideos {
                Stepper(
                    "Counts as Watched At \(Int((store.settings.hideWatchedThreshold * 100).rounded()))%",
                    value: $store.settings.hideWatchedThreshold, in: 0.5...1.0, step: 0.05
                )
                .accessibilityIdentifier(AccessibilityID.Settings.hideWatchedThresholdStepper)
            }
            #endif
            Toggle("Per-Device Recommendations", isOn: $store.settings.perDeviceRecommendationsEnabled)
                .accessibilityIdentifier(AccessibilityID.Settings.perDeviceRecommendationsToggle)
        } header: {
            Text("Feeds")
        } footer: {
            Text("Per-Device Recommendations lets YouTube tailor Home to this device. Off shows its general feed.")
        }
    }
}
