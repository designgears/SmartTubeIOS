#if os(tvOS)
import SmartTubeIOSCore
import SwiftUI
import UIKit

// MARK: - TVRootView

/// tvOS root: Apple TV app–style sidebar (tvOS 18+), top tabs on tvOS 17.
/// Owns the `TVNavigator` and presents the full-screen native player.
struct TVRootView: View {
    @State private var navigator = TVNavigator()
    /// Bumped when the active account changes; rebuilds every tab so pages reload the
    /// new account's feeds and on-device data (progress bars, history, queue…).
    @State private var accountGeneration = 0

    var body: some View {
        @Bindable var navigator = navigator
        Group {
            if #available(tvOS 18.0, *) {
                TVSidebarTabs()
            } else {
                TVLegacyTabs()
            }
        }
        .id(accountGeneration)
        .environment(navigator)
        .fullScreenCover(item: $navigator.nowPlaying) { request in
            TVPlayerScreen(video: request.video)
                .environment(navigator)
        }
        .onReceive(NotificationCenter.default.publisher(for: .activeChannelDidChange)) { _ in
            navigator.selection = .home
        }
        .onReceive(NotificationCenter.default.publisher(for: AccountScope.didChangeNotification)) { _ in
            navigator.resetForAccountChange()
            accountGeneration += 1
        }
        .onAppear {
            TVImagePipeline.screenScale = UIScreen.main.scale
            // UI tests: `--uitesting-deeplink-video=<id>` opens that video straight away
            // (same argument the iOS UI tests use).
            let prefix = "--uitesting-deeplink-video="
            if ProcessInfo.processInfo.arguments.contains("--uitesting"),
                let arg = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix(prefix) }),
                case let id = String(arg.dropFirst(prefix.count)), !id.isEmpty
            {
                navigator.play(Video(id: id, title: "", channelTitle: ""))
            }
        }
    }
}

// MARK: - Sidebar (tvOS 18+)

@available(tvOS 18.0, *)
private struct TVSidebarTabs: View {
    @Environment(TVNavigator.self) private var navigator
    @Environment(AuthService.self) private var auth

    var body: some View {
        @Bindable var navigator = navigator
        TabView(selection: $navigator.selection) {
            Tab("Home", systemImage: AppSymbol.home, value: TVTab.home) {
                TVTabStack(tab: .home) { TVHomeView() }
            }
            Tab("Subscriptions", systemImage: AppSymbol.subscriptions, value: TVTab.subscriptions) {
                TVTabStack(tab: .subscriptions) { TVFeedView(type: .subscriptions) }
            }
            Tab(value: TVTab.search, role: .search) {
                TVTabStack(tab: .search) { TVSearchView() }
            }
            Tab(
                auth.isSignedIn ? (auth.accountName ?? "Accounts") : (auth.savedAccounts.isEmpty ? "Sign In" : "Guest"),
                systemImage: AppSymbol.channel,
                value: TVTab.accounts
            ) {
                TVTabStack(tab: .accounts) { TVAccountsView() }
            }

            TabSection("Explore") {
                Tab("Music", systemImage: AppSymbol.music, value: TVTab.explore(.music)) {
                    TVTabStack(tab: .explore(.music)) { TVFeedView(type: .music) }
                }
                Tab("Gaming", systemImage: AppSymbol.gaming, value: TVTab.explore(.gaming)) {
                    TVTabStack(tab: .explore(.gaming)) { TVFeedView(type: .gaming) }
                }
                Tab("News", systemImage: AppSymbol.news, value: TVTab.explore(.news)) {
                    TVTabStack(tab: .explore(.news)) { TVFeedView(type: .news) }
                }
                Tab("Live", systemImage: AppSymbol.live, value: TVTab.explore(.live)) {
                    TVTabStack(tab: .explore(.live)) { TVFeedView(type: .live) }
                }
                Tab("Sports", systemImage: AppSymbol.sports, value: TVTab.explore(.sports)) {
                    TVTabStack(tab: .explore(.sports)) { TVFeedView(type: .sports) }
                }
            }

            TabSection("Library") {
                Tab("History", systemImage: AppSymbol.history, value: TVTab.history) {
                    TVTabStack(tab: .history) { TVFeedView(type: .history) }
                }
                Tab("Watch Later", systemImage: AppSymbol.watchLaterFill, value: TVTab.watchLater) {
                    TVTabStack(tab: .watchLater) { TVFeedView(type: .watchLater) }
                }
                Tab("Playlists", systemImage: AppSymbol.playlists, value: TVTab.playlists) {
                    TVTabStack(tab: .playlists) { TVFeedView(type: .playlists) }
                }
                Tab("Channels", systemImage: AppSymbol.accountsFill, value: TVTab.channels) {
                    TVTabStack(tab: .channels) { TVChannelsView() }
                }
                Tab("Queue", systemImage: AppSymbol.upNext, value: TVTab.queue) {
                    TVTabStack(tab: .queue) {
                        TVPlaylistView(playlistId: CurrentQueueStore.playlistID, title: "Queue")
                    }
                }
            }

            Tab("Settings", systemImage: AppSymbol.settings, value: TVTab.settings) {
                TVTabStack(tab: .settings, routable: false) { TVSettingsView() }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}

// MARK: - Top tabs (tvOS 17)

private struct TVLegacyTabs: View {
    @Environment(TVNavigator.self) private var navigator

    var body: some View {
        @Bindable var navigator = navigator
        TabView(selection: $navigator.selection) {
            TVTabStack(tab: .home) { TVHomeView() }
                .tabItem { Label("Home", systemImage: AppSymbol.home) }
                .tag(TVTab.home)
            TVTabStack(tab: .subscriptions) { TVFeedView(type: .subscriptions) }
                .tabItem { Label("Subscriptions", systemImage: AppSymbol.subscriptions) }
                .tag(TVTab.subscriptions)
            TVTabStack(tab: .search) { TVSearchView() }
                .tabItem { Label("Search", systemImage: AppSymbol.search) }
                .tag(TVTab.search)
            TVTabStack(tab: .history) { TVFeedView(type: .history) }
                .tabItem { Label("History", systemImage: AppSymbol.history) }
                .tag(TVTab.history)
            TVTabStack(tab: .accounts) { TVAccountsView() }
                .tabItem { Label("Accounts", systemImage: AppSymbol.channel) }
                .tag(TVTab.accounts)
            TVTabStack(tab: .settings, routable: false) { TVSettingsView() }
                .tabItem { Label("Settings", systemImage: AppSymbol.settings) }
                .tag(TVTab.settings)
        }
    }
}
#endif
