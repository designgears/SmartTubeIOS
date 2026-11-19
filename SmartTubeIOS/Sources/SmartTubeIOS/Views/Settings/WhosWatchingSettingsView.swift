import SmartTubeIOSCore
import SwiftUI

// MARK: - WhosWatchingSettingsView

/// Settings › Who's Watching: choose which profiles appear on the Who's Watching? screen.
/// Hiding one keeps it (and its accounts); it stays reachable from Settings › Accounts.
struct WhosWatchingSettingsView: View {
    @Environment(AuthService.self) private var auth

    var body: some View {
        List {
            Section {
                ForEach(auth.profileStore.profiles) { profile in
                    Toggle(isOn: shownBinding(profile)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile.name)
                            if let caption = caption(for: profile) {
                                Text(caption).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .accessibilityIdentifier(AccessibilityID.Settings.whosWatchingProfile(profile.id))
                }
            } header: {
                Text("Show on Who's Watching")
            } footer: {
                Text(
                    "Hidden profiles keep their accounts and can still be switched to from Settings. "
                        + "The profile in use is always shown.")
            }
        }
        .settingsPage(symbol: AppSymbol.accountsFill, caption: "Choose who appears on the Who's Watching? screen.")
        .navigationTitle("Who's Watching")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func shownBinding(_ profile: AppProfile) -> Binding<Bool> {
        Binding(
            get: { !auth.hiddenProfileIds.contains(profile.id) },
            set: { auth.setProfile(profile, hidden: !$0) }
        )
    }

    /// Handle, plus "In use" — two channels can share a name and photo.
    private func caption(for profile: AppProfile) -> String? {
        let parts = [profile.id == auth.activeProfileId ? "In use" : nil, profile.handle].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
