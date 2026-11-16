import SmartTubeIOSCore
import SwiftUI

// MARK: - WhosWatchingSettingsView

/// Settings › Who's Watching: choose which profiles (channels of the signed-in accounts)
/// appear on the Who's Watching? screen. Hiding one keeps it signed in; it stays
/// reachable from the Account section of Settings.
struct WhosWatchingSettingsView: View {
    @Environment(AuthService.self) private var auth

    var body: some View {
        List {
            Section {
                ForEach(auth.profiles) { profile in
                    Toggle(isOn: shownBinding(profile)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile.name)
                            if let caption = caption(for: profile) {
                                Text(caption).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .accessibilityIdentifier("settings.whosWatching.\(profile.id)")
                }
            } header: {
                Text("Show on Who's Watching")
            } footer: {
                Text(
                    "Hidden profiles stay signed in and can still be switched to from Settings. "
                        + "The profile in use is always shown.")
            }
        }
        .navigationTitle("Who's Watching")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func shownBinding(_ profile: AccountProfile) -> Binding<Bool> {
        Binding(
            get: { !auth.hiddenProfileIds.contains(profile.id) },
            set: { auth.setProfile(profile, hidden: !$0) }
        )
    }

    /// Handle, plus "In use" — two channels can share a name and photo.
    private func caption(for profile: AccountProfile) -> String? {
        let parts = [profile.id == auth.activeProfileId ? "In use" : nil, profile.handle].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
