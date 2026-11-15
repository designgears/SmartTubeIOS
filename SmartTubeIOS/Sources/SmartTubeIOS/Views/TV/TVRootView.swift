#if os(tvOS)
import SmartTubeIOSCore
import SwiftUI
import UIKit

// MARK: - TVRootView

/// tvOS root: Apple TV app–style sidebar (tvOS 18+), top tabs on tvOS 17.
/// Owns the `TVNavigator` and presents the full-screen native player.
struct TVRootView: View {
    @State private var navigator = TVNavigator()

    var body: some View {
        @Bindable var navigator = navigator
        Group {
            if #available(tvOS 18.0, *) {
                TVSidebarTabs()
            } else {
                TVLegacyTabs()
            }
        }
        .environment(navigator)
        .fullScreenCover(item: $navigator.nowPlaying) { request in
            TVPlayerScreen(video: request.video)
                .environment(navigator)
        }
        .onReceive(NotificationCenter.default.publisher(for: .activeChannelDidChange)) { _ in
            navigator.selection = .home
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
            Tab("Home", systemImage: "house.fill", value: TVTab.home) {
                TVTabStack(tab: .home) { TVHomeView() }
            }
            Tab("Subscriptions", systemImage: "play.square.stack.fill", value: TVTab.subscriptions) {
                TVTabStack(tab: .subscriptions) { TVFeedView(type: .subscriptions) }
            }
            Tab(value: TVTab.search, role: .search) {
                TVTabStack(tab: .search) { TVSearchView() }
            }
            Tab(
                auth.isSignedIn ? (auth.accountName ?? "Accounts") : "Sign In",
                systemImage: "person.crop.circle.fill",
                value: TVTab.accounts
            ) {
                TVTabStack(tab: .accounts) { TVAccountsView() }
            }

            TabSection("Explore") {
                Tab("Music", systemImage: "music.note", value: TVTab.explore(.music)) {
                    TVTabStack(tab: .explore(.music)) { TVFeedView(type: .music) }
                }
                Tab("Gaming", systemImage: "gamecontroller.fill", value: TVTab.explore(.gaming)) {
                    TVTabStack(tab: .explore(.gaming)) { TVFeedView(type: .gaming) }
                }
                Tab("News", systemImage: "newspaper.fill", value: TVTab.explore(.news)) {
                    TVTabStack(tab: .explore(.news)) { TVFeedView(type: .news) }
                }
                Tab("Live", systemImage: "dot.radiowaves.left.and.right", value: TVTab.explore(.live)) {
                    TVTabStack(tab: .explore(.live)) { TVFeedView(type: .live) }
                }
                Tab("Sports", systemImage: "sportscourt.fill", value: TVTab.explore(.sports)) {
                    TVTabStack(tab: .explore(.sports)) { TVFeedView(type: .sports) }
                }
            }

            TabSection("Library") {
                Tab("History", systemImage: "clock.arrow.circlepath", value: TVTab.history) {
                    TVTabStack(tab: .history) { TVFeedView(type: .history) }
                }
                Tab("Watch Later", systemImage: "clock.fill", value: TVTab.watchLater) {
                    TVTabStack(tab: .watchLater) { TVFeedView(type: .watchLater) }
                }
                Tab("Playlists", systemImage: "list.bullet.rectangle.fill", value: TVTab.playlists) {
                    TVTabStack(tab: .playlists) { TVFeedView(type: .playlists) }
                }
                Tab("Channels", systemImage: "person.2.fill", value: TVTab.channels) {
                    TVTabStack(tab: .channels) { TVChannelsView() }
                }
                Tab("Queue", systemImage: "text.line.first.and.arrowtriangle.forward", value: TVTab.queue) {
                    TVTabStack(tab: .queue) {
                        TVPlaylistView(playlistId: CurrentQueueStore.playlistID, title: "Queue")
                    }
                }
            }

            Tab("Settings", systemImage: "gearshape.fill", value: TVTab.settings) {
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
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(TVTab.home)
            TVTabStack(tab: .subscriptions) { TVFeedView(type: .subscriptions) }
                .tabItem { Label("Subscriptions", systemImage: "play.square.stack.fill") }
                .tag(TVTab.subscriptions)
            TVTabStack(tab: .search) { TVSearchView() }
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .tag(TVTab.search)
            TVTabStack(tab: .history) { TVFeedView(type: .history) }
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                .tag(TVTab.history)
            TVTabStack(tab: .accounts) { TVAccountsView() }
                .tabItem { Label("Accounts", systemImage: "person.crop.circle.fill") }
                .tag(TVTab.accounts)
            TVTabStack(tab: .settings, routable: false) { TVSettingsView() }
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(TVTab.settings)
        }
    }
}
#endif
