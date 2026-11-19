import SmartTubeIOSCore
import SwiftUI

// MARK: - ProfileEditorView

/// A profile's page: its name, its YouTube accounts (and which is the main one), switching to
/// it, and deleting it. Opened from Who's Watching? (tvOS) and Settings › Accounts.
struct ProfileEditorView: View {
    let profileId: String
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""
    @State private var isRenaming = false
    @State private var isConfirmingDelete = false
    @State private var showSignIn = false

    private var profile: AppProfile? { auth.profileStore.profile(id: profileId) }

    var body: some View {
        Form {
            if let profile {
                general(profile)
                youTube(profile)
                Section {
                    Button("Delete Profile", role: .destructive) { isConfirmingDelete = true }
                        .accessibilityIdentifier(AccessibilityID.Profiles.deleteButton)
                } footer: {
                    Text("Its history, watched marks and settings on this device go too. Its accounts stay signed in.")
                }
            }
        }
        .settingsPage(
            imageURL: profile?.avatarURL, fallbackSymbol: AppSymbol.person,
            caption: "Everything this person watches with, kept together."
        )
        .navigationTitle(profile?.name ?? "Profile")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .alert("Rename Profile", isPresented: $isRenaming) {
            TextField("Name", text: $newName)
            Button("Save") { if let profile { auth.renameProfile(profile, to: newName) } }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Delete \(profile?.name ?? "this profile")?", isPresented: $isConfirmingDelete) {
            Button("Delete", role: .destructive) {
                if let profile { auth.deleteProfile(profile) }
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(
            isPresented: $showSignIn,
            onDismiss: {
                // Closed without finishing: back to the account that was live.
                if !auth.isSignedIn || auth.profileStore.addAccountTarget != nil { auth.cancelSignIn() }
            },
            content: { SignInView() }
        )
    }

    private func general(_ profile: AppProfile) -> some View {
        Section {
            if profile.id != auth.activeProfileId {
                Button("Switch to This Profile") { auth.switchToProfile(profile) }
                    .accessibilityIdentifier(AccessibilityID.Profiles.switchButton)
            }
            Button {
                newName = profile.name
                isRenaming = true
            } label: {
                LabeledContent("Name", value: profile.name)
            }
            .accessibilityIdentifier(AccessibilityID.Profiles.renameButton)
        }
    }

    private func youTube(_ profile: AppProfile) -> some View {
        Section {
            ForEach(profile.youtube, id: \.self) { key in
                let channel = auth.youTubeChannel(key)
                let isMain = key == profile.mainYouTube
                Menu {
                    if !isMain {
                        Button("Make Main Account", systemImage: AppSymbol.mainAccount) {
                            auth.makeMainYouTube(key, in: profile)
                        }
                    }
                    Button("Remove from Profile", systemImage: AppSymbol.trash, role: .destructive) {
                        auth.removeYouTube(key, from: profile)
                    }
                } label: {
                    SettingsProfileLabel(
                        name: channel?.name ?? "YouTube account",
                        caption: [isMain ? "Main" : nil, channel?.handle].compactMap { $0 }.joined(separator: " · "),
                        avatarURL: channel?.avatarURL, isCurrent: isMain)
                }
            }
            Menu {
                ForEach(auth.youTubeChannels(notIn: profile)) { channel in
                    Button(channel.displayLabel) {
                        auth.addYouTube(
                            YouTubeAccountKey(accountId: channel.accountId, pageId: channel.pageId), to: profile)
                    }
                }
                Button("Sign In to Another Account", systemImage: AppSymbol.plus) {
                    auth.prepareToAddYouTubeAccount(to: profile)
                    showSignIn = true
                }
            } label: {
                Label("Add YouTube Account", systemImage: AppSymbol.plus)
            }
            .accessibilityIdentifier(AccessibilityID.Profiles.addYouTubeButton)
        } header: {
            Text("YouTube")
        } footer: {
            Text(
                "Subscriptions, channels and live streams of every account are combined. The main account (✓) "
                    + "plays videos and keeps watch history, likes and Watch Later.")
        }
    }
}
