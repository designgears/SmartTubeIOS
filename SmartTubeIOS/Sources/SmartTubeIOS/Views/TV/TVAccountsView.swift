#if os(tvOS)
import SmartTubeIOSCore
import SwiftUI

// MARK: - TVAccountsView

/// "Who's watching?" — the people on this Apple TV. Select one to switch (their feeds,
/// history, settings and accounts follow); long-press to edit or hide it. "Guest" is signed-out
/// use with its own on-device data, without signing anyone out.
struct TVAccountsView: View {
    @Environment(AuthService.self) private var auth
    @Environment(TVNavigator.self) private var navigator
    @State private var showSignIn = false
    @State private var isNamingProfile = false
    @State private var newProfileName = ""

    private var hasProfiles: Bool { !auth.profileStore.profiles.isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TVPageHeader(
                    title: hasProfiles ? "Who's Watching?" : "Sign In",
                    subtitle: hasProfiles
                        ? "Everyone keeps their own accounts, feed, history and settings."
                        : "Sign in, or add a profile to keep your own history and settings."
                )
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 250, maximum: 290), spacing: 40, alignment: .top)],
                    spacing: 56
                ) {
                    // Every profile, minus the ones hidden in Settings › Who's Watching.
                    ForEach(auth.whosWatchingAppProfiles) { profile in
                        profileCard(profile)
                    }
                    if hasProfiles || !auth.savedAccounts.isEmpty {
                        // Signed-out use with its own history/settings; nobody is signed out.
                        TVAddAccountCard(
                            title: "Guest", symbol: AppSymbol.person, subtitle: auth.isGuest ? "Current" : nil
                        ) {
                            auth.switchToGuest()
                            navigator.selection = .home
                        }
                    }
                    TVAddAccountCard(title: "Add Profile") {
                        newProfileName = ""
                        isNamingProfile = true
                    }
                    .accessibilityIdentifier(AccessibilityID.Profiles.addProfileCard)
                    if !hasProfiles {
                        // A first Google sign-in makes the first profile.
                        TVAddAccountCard(title: "Sign In", symbol: AppSymbol.personCircle) {
                            auth.prepareToAddAccount()
                            showSignIn = true
                        }
                    }
                }
                .padding(.horizontal, TVLayout.pageInset)
                .padding(.vertical, 24)
                .focusSection()
            }
            .padding(.bottom, 80)
        }
        .fullScreenCover(
            isPresented: $showSignIn,
            onDismiss: {
                // Closed without finishing: return to the previous account.
                if !auth.isSignedIn { auth.cancelSignIn() }
            },
            content: { SignInView() }
        )
        .alert("New Profile", isPresented: $isNamingProfile) {
            TextField("Name", text: $newProfileName)
            Button("Create") {
                let profile = auth.createProfile(named: newProfileName)
                navigator.open(.profile(id: profile.id))
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Then add their YouTube accounts.")
        }
    }

    private func profileCard(_ profile: AppProfile) -> some View {
        let isCurrent = profile.id == auth.activeProfileId
        return TVChannelCard(
            title: profile.name,
            thumbnailURL: profile.avatarURL,
            // The handle tells apart channels that share a name and photo.
            subtitle: [isCurrent ? "Current" : nil, profile.handle ?? summary(of: profile)].compactMap { $0 }
                .joined(separator: " · ").nilIfEmpty
        ) {
            if !isCurrent { auth.switchToProfile(profile) }
            navigator.selection = .home
        }
        .contextMenu {
            Button("Edit Profile", systemImage: AppSymbol.edit) {
                navigator.open(.profile(id: profile.id))
            }
            if !isCurrent {
                Button("Hide from Who's Watching", systemImage: AppSymbol.hide) {
                    auth.setProfile(profile, hidden: true)
                }
            }
        }
    }

    /// "2 YouTube accounts" / "No accounts" for profiles without a handle to show.
    private func summary(of profile: AppProfile) -> String? {
        switch profile.youtube.count {
        case 0: "No accounts yet"
        case 1: nil
        case let count: "\(count) YouTube accounts"
        }
    }
}

struct TVAddAccountCard: View {
    let title: String
    var symbol: String = AppSymbol.plus
    var subtitle: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 18) {
                ZStack {
                    Circle().fill(Color.white.opacity(0.1))
                    Image(systemName: symbol).font(.system(size: 64, weight: .medium)).foregroundStyle(
                        .secondary)
                }
                .frame(width: TVLayout.channelSize, height: TVLayout.channelSize)
                .clipShape(Circle())
                .modifier(TVAvatarFocus())
                Text(title)
                    .font(.callout.weight(.semibold))
                    .frame(width: TVLayout.channelSize + 60)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(TVPlainFocusButtonStyle())
    }
}
#endif
