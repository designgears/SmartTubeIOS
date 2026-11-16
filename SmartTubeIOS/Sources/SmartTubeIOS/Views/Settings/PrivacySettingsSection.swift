import SmartTubeIOSCore
import SwiftUI

// MARK: - History & Privacy

/// Watch history, iCloud sync and on-device diagnostics.
struct PrivacySettingsSection: View {
    @Environment(SettingsStore.self) private var store

    var body: some View {
        @Bindable var store = store
        Section {
            Toggle("Watch History", isOn: watchHistory)
                .accessibilityIdentifier(AccessibilityID.Settings.watchHistoryToggle)
            if !LocalWatchHistoryStore.shared.entries.isEmpty {
                Button("Clear Watch History on This Device", role: .destructive) {
                    LocalWatchHistoryStore.shared.clear()
                }
                .accessibilityIdentifier(AccessibilityID.Settings.clearLocalHistoryButton)
            }
            Toggle("Sync to iCloud", isOn: $store.settings.iCloudSyncEnabled)
                .accessibilityIdentifier(AccessibilityID.Settings.iCloudSyncToggle)
            Toggle("Diagnostic Logging", isOn: diagnosticLogging)
                .accessibilityIdentifier(AccessibilityID.Settings.disableAnalyticsToggle)
        } header: {
            Text("History & Privacy")
        } footer: {
            Text(
                "Watch history is kept on this device; SmartTube also reports watches to your YouTube account, which "
                    + "doesn't always record them. Diagnostic logs never leave this device unless you save a report "
                    + "and share it; turning logging on or off applies the next time SmartTube starts.")
        }
    }

    private var watchHistory: Binding<Bool> {
        Binding(
            get: { store.settings.historyState == .enabled },
            set: { store.settings.historyState = $0 ? .enabled : .disabled }
        )
    }

    private var diagnosticLogging: Binding<Bool> {
        Binding(get: { !store.settings.disableAnalytics }, set: { store.settings.disableAnalytics = !$0 })
    }
}
