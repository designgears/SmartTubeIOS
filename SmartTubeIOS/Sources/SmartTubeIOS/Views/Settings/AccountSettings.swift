import SmartTubeIOSCore
import SwiftUI

// MARK: - Account section

/// The top of Settings: who's using the app, one row. Everything else about accounts —
/// switching, Guest, adding, signing out — lives on the Accounts page it opens.
struct AccountSettingsSection: View {
    @Environment(AuthService.self) private var auth
    @State private var showSignIn = false

    var body: some View {
        Section("Account") {
            if auth.savedAccounts.isEmpty {
                Button("Sign in with Google") { showSignIn = true }
                    .accessibilityIdentifier(AccessibilityID.Settings.signInButton)
            } else {
                NavigationLink {
                    AccountsSettingsView()
                } label: {
                    if let profile = currentProfile {
                        SettingsProfileLabel(
                            name: profile.name, caption: profile.handle ?? "Switch, add or sign out",
                            avatarURL: profile.avatarURL, size: .large)
                    } else {
                        SettingsProfileLabel(
                            name: "Guest", caption: Self.profileCount(auth.profiles.count), symbol: AppSymbol.person,
                            size: .large)
                    }
                }
                .accessibilityIdentifier(AccessibilityID.Settings.accountsLink)
            }
        }
        .sheet(isPresented: $showSignIn) { SignInView() }
    }

    private var currentProfile: AccountProfile? {
        guard let id = auth.activeProfileId else { return nil }
        return auth.profiles.first { $0.id == id }
    }

    static func profileCount(_ count: Int) -> String {
        count == 1 ? "1 profile on this device" : "\(count) profiles on this device"
    }
}

// MARK: - Accounts page

/// Settings › Accounts: every profile (each channel of each signed-in Google account) and
/// Guest — tap to switch — then adding and signing out of Google accounts.
struct AccountsSettingsView: View {
    @Environment(AuthService.self) private var auth
    @State private var showAddAccount = false
    @State private var accountToSignOut: SavedAccount?

    var body: some View {
        Form {
            Section {
                ForEach(auth.profiles) { profile in
                    Button {
                        auth.switchProfile(profile)
                    } label: {
                        SettingsProfileLabel(
                            name: profile.name, caption: profile.handle, avatarURL: profile.avatarURL,
                            isCurrent: profile.id == auth.activeProfileId)
                    }
                }
                Button {
                    auth.switchToGuest()
                } label: {
                    SettingsProfileLabel(
                        name: "Guest", caption: "Not signed in", symbol: AppSymbol.person, isCurrent: auth.isGuest)
                }
                .accessibilityIdentifier(AccessibilityID.Settings.useAsGuestButton)
            } header: {
                Text("Profiles")
            } footer: {
                Text("Each profile keeps its own feed, history, queue and settings.")
            }

            #if os(tvOS)
            // Who's Watching? is the tvOS profile picker; iOS has none.
            if auth.profiles.count > 1 {
                Section {
                    NavigationLink {
                        WhosWatchingSettingsView()
                    } label: {
                        LabeledContent("Who's Watching", value: whosWatchingSummary)
                    }
                    .accessibilityIdentifier(AccessibilityID.Settings.whosWatchingLink)
                }
            }
            #endif

            Section {
                Button("Add Account") {
                    auth.prepareToAddAccount()
                    showAddAccount = true
                }
                .accessibilityIdentifier(AccessibilityID.Settings.addAccountButton)
                ForEach(auth.savedAccounts) { account in
                    Button("Sign Out of \(Self.name(of: account))", role: .destructive) {
                        accountToSignOut = account
                    }
                }
            } header: {
                Text("Google Accounts")
            } footer: {
                Text("Signing out of an account removes all of its channels from this device.")
            }
        }
        .settingsPage(
            imageURL: auth.isSignedIn ? auth.accountAvatarURL : nil, fallbackSymbol: AppSymbol.accountsFill,
            caption: "Switch profiles, add an account, or sign out."
        )
        .navigationTitle("Accounts")
        #if os(iOS)
        .toolbar(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        // On the form, not the button: starting an add signs the current account out of the
        // session, which can remove the row the button is in (and a sheet attached to it).
        .sheet(
            isPresented: $showAddAccount,
            onDismiss: {
                // Closed without finishing: go back to the previous account.
                if !auth.isSignedIn { auth.cancelSignIn() }
            },
            content: { SignInView() }
        )
        .alert(
            "Sign out of \(accountToSignOut.map(Self.name(of:)) ?? "this account")?",
            isPresented: Binding(get: { accountToSignOut != nil }, set: { if !$0 { accountToSignOut = nil } }),
            presenting: accountToSignOut
        ) { account in
            Button("Sign Out", role: .destructive) { auth.removeAccount(account.id) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Its channels, and their history and settings on this device, are removed.")
        }
    }

    /// "All" or "2 of 3".
    private var whosWatchingSummary: String {
        let all = auth.profiles.count
        let shown = auth.profiles.filter { !auth.hiddenProfileIds.contains($0.id) }.count
        return shown == all ? "All" : "\(shown) of \(all)"
    }

    /// The Google account's own name — signing out removes all of its channels.
    private static func name(of account: SavedAccount) -> String {
        account.primaryName ?? account.displayName ?? "Account"
    }
}

// MARK: - Profile row

/// Avatar, name and a caption (handle, status) — the account rows in Settings.
struct SettingsProfileLabel: View {
    enum Size {
        case regular, large

        var points: CGFloat {
            #if os(tvOS)
            self == .large ? 72 : 56
            #else
            self == .large ? 44 : 32
            #endif
        }
    }

    let name: String
    var caption: String?
    var avatarURL: URL?
    var symbol: String = AppSymbol.person
    var size: Size = .regular
    var isCurrent = false

    var body: some View {
        HStack(spacing: 14) {
            avatar
            VStack(alignment: .leading, spacing: 2) {
                // Explicit colours: a Form button would tint its label like a link.
                Text(name).foregroundStyle(Color.primary).lineLimit(1)
                if let caption {
                    Text(caption).font(.caption).foregroundStyle(Color.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if isCurrent {
                Image(systemName: AppSymbol.checkmark)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityLabel("Current")
            }
        }
        .contentShape(Rectangle())
    }

    private var avatar: some View {
        ZStack {
            Circle().fill(Color.secondary.opacity(0.25))
            Image(systemName: symbol)
                .font(.system(size: size.points * 0.45))
                .foregroundStyle(Color.secondary)
            if let avatarURL {
                AsyncImage(url: avatarURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.clear
                }
            }
        }
        .frame(width: size.points, height: size.points)
        .clipShape(Circle())
    }
}
