#if os(tvOS)
import SmartTubeIOSCore
import SwiftUI

// MARK: - TVAccountsView

/// "Who's watching?" — every Google account signed in on this Apple TV. Select one to
/// switch (feeds, history and subscriptions follow it); long-press to sign it out.
/// "Guest" is signed-out use with its own on-device data, without signing anyone out.
struct TVAccountsView: View {
    @Environment(AuthService.self) private var auth
    @Environment(TVNavigator.self) private var navigator
    @State private var showSignIn = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TVPageHeader(
                    title: auth.savedAccounts.isEmpty ? "Sign In" : "Who's Watching?",
                    subtitle: auth.profiles.count > 1
                        ? "Every channel keeps its own feed, history and settings."
                        : "Add more accounts to switch between them here."
                )
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 250, maximum: 290), spacing: 40, alignment: .top)],
                    spacing: 56
                ) {
                    // One card per channel (primary and Brand Accounts) of every signed-in account.
                    ForEach(auth.profiles) { profile in
                        let isCurrent = profile.id == auth.activeProfileId
                        TVChannelCard(
                            title: profile.name,
                            thumbnailURL: profile.avatarURL,
                            // The handle tells apart channels that share a name and photo.
                            subtitle: [isCurrent ? "Current" : nil, profile.handle].compactMap { $0 }
                                .joined(separator: " · ").nilIfEmpty
                        ) {
                            if !isCurrent { auth.switchProfile(profile) }
                            navigator.selection = .home
                        }
                        .contextMenu {
                            Button(
                                "Sign Out of \(accountName(profile.accountId))", systemImage: AppSymbol.signOut,
                                role: .destructive
                            ) {
                                auth.removeAccount(profile.accountId)
                            }
                        }
                    }
                    if !auth.savedAccounts.isEmpty {
                        // Signed-out use with its own history/settings; nobody is signed out.
                        TVAddAccountCard(
                            title: "Guest", symbol: AppSymbol.person, subtitle: auth.isGuest ? "Current" : nil
                        ) {
                            auth.switchToGuest()
                            navigator.selection = .home
                        }
                    }
                    TVAddAccountCard(title: auth.savedAccounts.isEmpty ? "Sign In" : "Add Account") {
                        auth.prepareToAddAccount()
                        showSignIn = true
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
    }
}

extension TVAccountsView {
    /// The Google account's own name: Sign Out removes all of its channels.
    fileprivate func accountName(_ accountId: String) -> String {
        let account = auth.savedAccounts.first { $0.id == accountId }
        return account?.primaryName ?? account?.displayName ?? "Account"
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

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
#endif
