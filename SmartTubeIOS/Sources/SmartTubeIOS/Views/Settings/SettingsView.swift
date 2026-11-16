import SmartTubeIOSCore
import SwiftUI

// MARK: - SettingsView

/// App settings: one section per topic, each its own view (`*SettingsSection`); deeper
/// pages (Accounts, SponsorBlock, Visible Sections…) open from their section.
public struct SettingsView: View {
    @Environment(SettingsStore.self) private var store
    /// #126: whether this visit to Settings has passed the PIN check. Reset on disappear so
    /// leaving and coming back (e.g. switching tabs) locks it again.
    @State private var isUnlocked = false

    public init() {}

    public var body: some View {
        Group {
            if let pinHash = store.settings.settingsPINHash, !isUnlocked {
                SettingsPINLockView(expectedHash: pinHash) { isUnlocked = true }
            } else {
                settingsForm
            }
        }
        .onDisappear {
            if store.settings.settingsPINHash != nil { isUnlocked = false }
        }
    }

    private var settingsForm: some View {
        Form {
            AccountSettingsSection()
            PlaybackSettingsSection()
            FeedSettingsSection()
            #if !os(tvOS)
            AppearanceSettingsSection()
            #endif
            PrivacySettingsSection()
            CommunitySettingsSection()
            ParentalControlsSettingsSection()
            #if os(macOS)
            ExperimentalSettingsSection()
            #endif
            AboutSettingsSection()
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        #if os(tvOS)
        // Navigation-link pickers (the tvOS default) push a blank, unfocusable page
        // inside the sidebar TabView, which traps the Siri Remote. Menu pickers show
        // their options in a native popup instead — no push.
        .pickerStyle(.menu)
        #endif
        // Hide the blank navigation bar on iOS and tvOS — a visible nav bar on tvOS
        // conflicts with the TabView tab bar scroll-hide animation (issue #102 / gh-34).
        #if !os(macOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
    }
}
