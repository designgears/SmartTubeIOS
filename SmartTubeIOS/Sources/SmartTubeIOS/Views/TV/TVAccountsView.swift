#if os(tvOS)
import SmartTubeIOSCore
import SwiftUI

// MARK: - TVAccountsView

/// "Who's watching?" — every Google account signed in on this Apple TV. Select one to
/// switch (feeds, history and subscriptions follow it); long-press to sign it out.
struct TVAccountsView: View {
    @Environment(AuthService.self) private var auth
    @Environment(TVNavigator.self) private var navigator
    @State private var showSignIn = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TVPageHeader(
                    title: auth.savedAccounts.isEmpty ? "Sign In" : "Who's Watching?",
                    subtitle: auth.savedAccounts.count > 1
                        ? "Your feed, history and subscriptions follow the account you pick."
                        : "Add more accounts to switch between them here."
                )
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 250, maximum: 290), spacing: 40, alignment: .top)],
                    spacing: 56
                ) {
                    ForEach(auth.savedAccounts) { account in
                        let isCurrent = account.id == auth.activeAccountId && auth.isSignedIn
                        TVChannelCard(
                            title: account.displayName ?? account.primaryName ?? "Account",
                            thumbnailURL: account.displayAvatarURL,
                            subtitle: isCurrent ? "Current" : nil
                        ) {
                            if !isCurrent { auth.switchAccount(to: account.id) }
                            navigator.selection = .home
                        }
                        .contextMenu {
                            Button("Sign Out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                                auth.removeAccount(account.id)
                            }
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
            }
        ) {
            SignInView()
        }
    }
}

struct TVAddAccountCard: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 18) {
                ZStack {
                    Circle().fill(Color.white.opacity(0.1))
                    Image(systemName: "plus").font(.system(size: 64, weight: .medium)).foregroundStyle(.secondary)
                }
                .frame(width: TVLayout.channelSize, height: TVLayout.channelSize)
                .clipShape(Circle())
                .modifier(TVAvatarFocus())
                Text(title)
                    .font(.callout.weight(.semibold))
                    .frame(width: TVLayout.channelSize + 60)
            }
        }
        .buttonStyle(TVPlainFocusButtonStyle())
    }
}
#endif
