#if os(tvOS)
import SmartTubeIOSCore
import SwiftUI

// MARK: - BrowseViewModel loading helper

/// Loads a `BrowseViewModel` section once per auth token. Signed in: hand the token to
/// the view model (which reloads itself). Signed out: reload explicitly.
@MainActor
func tvStartBrowse(_ vm: BrowseViewModel, section: BrowseSection, token: String?) async {
    if let token {
        await vm.updateAuthToken(token)
    } else {
        vm.reload(section: section)
    }
}

// MARK: - TVFeedView

/// Full-page grid for one browse section (Subscriptions, History, Watch Later,
/// Playlists, Explore categories).
struct TVFeedView: View {
    let type: BrowseSection.SectionType

    @Environment(\.innerTubeAPI) private var api
    @Environment(AuthService.self) private var auth
    @Environment(SettingsStore.self) private var store
    @Environment(TVNavigator.self) private var navigator
    @State private var vm: BrowseViewModel?
    @State private var startedToken: String?? = .none
    @State private var showSignIn = false
    private var follows: ExternalFollowStore { .shared }
    private var externalLive: ExternalLiveStore { .shared }
    private var externalFeed: ExternalFeedStore { .shared }

    private var section: BrowseSection { BrowseSection(type: type) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TVPageHeader(title: title, subtitle: subtitle)
                content
            }
            .padding(.bottom, 80)
        }
        .task(id: auth.accessToken) {
            let token = auth.accessToken
            if case .some(let started) = startedToken, started == token {
                vm?.refreshIfStale()
                return
            }
            startedToken = .some(token)
            if vm == nil { vm = BrowseViewModel(api: api, initialSection: section) }
            if let vm { await tvStartBrowse(vm, section: section, token: token) }
        }
        // Subscriptions blend in the profile's Twitch and Kick follows: who's live, and their
        // latest past broadcasts.
        .task(id: type == .subscriptions ? follows.all.map(\.id) : []) {
            guard type == .subscriptions, !follows.all.isEmpty else { return }
            async let live: Void = externalLive.refresh(channels: follows.all)
            await externalFeed.refresh(channels: follows.all)
            await live
        }
    }

    @ViewBuilder private var content: some View {
        let all = visibleVideos
        // Subscriptions lead with whoever is live now; the feed is newest-first by publish
        // date, which live streams don't have, so they'd otherwise sink to the bottom.
        let live = type == .subscriptions ? all.filter(\.isLive) : []
        let videos = live.isEmpty ? all : all.filter { !$0.isLive }
        if !live.isEmpty {
            TVShelf(title: "Live", items: live, prefetchWidth: TVLayout.cardWidth) { video in
                TVVideoCard(video: video) { navigator.play(video) }
            }
        }
        if let vm, !videos.isEmpty {
            TVVideoGrid(
                videos: videos,
                onReachEnd: {
                    if let last = vm.videoGroups.last?.videos.last { vm.loadMoreIfNeeded(lastVideo: last) }
                },
                pageKey: vm.videoGroups.flatMap(\.videos).count,
                onSelect: { navigator.play($0) }
            )
        } else if !live.isEmpty {
            EmptyView()
        } else if vm == nil || vm?.isLoading == true {
            TVLoadingView().frame(height: 700)
        } else if needsSignIn {
            TVSignInPrompt(title: "Sign in to see \(title)", message: signInMessage).frame(height: 700)
        } else if let error = vm?.error {
            TVMessageView(
                systemImage: AppSymbol.warningOutline,
                title: "Couldn't load \(title)",
                message: error.localizedDescription,
                actionTitle: "Try Again"
            ) { vm?.reload(section: section) }
            .frame(height: 700)
        } else if type == .subscriptions && !auth.isSignedIn {
            TVMessageView(
                systemImage: emptyIcon, title: emptyTitle, message: emptyMessage,
                actionTitle: "Sign In", action: { showSignIn = true },
                secondaryTitle: "Find Channels", secondaryAction: { navigator.selection = .search }
            )
            .frame(height: 700)
            .fullScreenCover(isPresented: $showSignIn) { SignInView() }
        } else {
            TVMessageView(
                systemImage: emptyIcon, title: emptyTitle, message: emptyMessage,
                actionTitle: "Refresh", action: { vm?.reload(section: section) },
                secondaryTitle: "Go Home", secondaryAction: { navigator.selection = .home }
            )
            .frame(height: 700)
        }
    }

    private var visibleVideos: [Video] {
        var feed = (vm?.videoGroups.flatMap(\.videos) ?? []).uniquedByID()
        if type == .subscriptions {
            let isComplete = vm.map { !$0.isLoading && $0.videoGroups.last?.nextPageToken == nil } ?? false
            feed =
                externalLive.videos
                + ExternalFeedStore.blended(feed, with: externalFeed.videos, feedIsComplete: isComplete)
        }
        let all = feed.hidingWatched(in: type, settings: store.settings)
        guard store.settings.hideShorts, type != .shorts else { return all }
        return all.filter { !$0.isShort }
    }

    private var needsSignIn: Bool {
        if vm?.isAuthRequired == true { return true }
        return [.watchLater, .playlists].contains(type) && !auth.isSignedIn
    }

    private var title: String {
        switch type {
        case .watchLater: return "Watch Later"
        default: return section.title
        }
    }

    private var subtitle: String? {
        switch type {
        case .subscriptions where !auth.isSignedIn: return "Latest from channels you follow"
        case .history where !auth.isSignedIn: return "Watched on this Apple TV"
        default: return nil
        }
    }

    private var signInMessage: String {
        "Your \(title.lowercased()) are tied to your YouTube account."
    }

    private var emptyIcon: String {
        switch type {
        case .subscriptions: return "play.square.stack"
        case .history: return "clock.arrow.circlepath"
        case .watchLater: return "clock"
        case .playlists: return "list.bullet.rectangle"
        default: return "sparkles.tv"
        }
    }

    private var emptyTitle: String {
        switch type {
        case .subscriptions: return "No subscription videos yet"
        case .history: return "Nothing watched yet"
        case .watchLater: return "Watch Later is empty"
        case .playlists: return "No playlists"
        default: return "Nothing here right now"
        }
    }

    private var emptyMessage: String? {
        switch type {
        case .subscriptions where !auth.isSignedIn:
            return "Follow channels from their channel page, or sign in to use your YouTube subscriptions."
        case .history: return "Videos you watch will show up here."
        default: return nil
        }
    }
}

// MARK: - TVChannelsView

/// Grid of subscribed (or locally followed) channels.
struct TVChannelsView: View {
    @Environment(\.innerTubeAPI) private var api
    @Environment(AuthService.self) private var auth
    @Environment(TVNavigator.self) private var navigator
    @Environment(SettingsStore.self) private var store
    @State private var vm: BrowseViewModel?
    @State private var startedToken: String?? = .none
    @State private var showSignIn = false
    private var live: SubscriptionLiveStore { .shared }
    private var follows: ExternalFollowStore { .shared }
    private var externalLive: ExternalLiveStore { .shared }

    private let section = BrowseSection(type: .channels)

    /// YouTube subscriptions and the profile's Twitch and Kick follows, in the chosen order,
    /// live channels first.
    private var channels: [Channel] {
        store.settings.channelSort.sorted((vm?.subscribedChannels ?? []) + follows.all, isLive: isLive)
    }

    private func isLive(_ channel: Channel) -> Bool {
        channel.platform == .youtube ? live.isLive(channel) : externalLive.liveVideo(of: channel.id) != nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TVPageHeader(
                    title: "Channels", subtitle: auth.isSignedIn ? nil : "Channels you follow on this Apple TV")
                if !channels.isEmpty {
                    sortMenu
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 250, maximum: 290), spacing: 40, alignment: .top)],
                        spacing: 56
                    ) {
                        ForEach(channels) { channel in
                            TVChannelCard(
                                title: channel.title,
                                thumbnailURL: channel.thumbnailURL,
                                subtitle: channel.platform == .youtube
                                    ? channel.subscriberCount : channel.platform.title,
                                isLive: isLive(channel),
                                platform: channel.platform
                            ) {
                                navigator.open(.channel(id: channel.id, title: channel.title))
                            }
                        }
                    }
                    .padding(.horizontal, TVLayout.pageInset)
                    .padding(.vertical, 24)
                    .focusSection()
                } else if vm == nil || vm?.isLoading == true {
                    TVLoadingView().frame(height: 700)
                } else if auth.isSignedIn {
                    TVMessageView(
                        systemImage: AppSymbol.accounts,
                        title: "No channels yet",
                        message: "Channels you subscribe to on YouTube appear here.",
                        actionTitle: "Refresh", action: { vm?.reload(section: section) }
                    )
                    .frame(height: 700)
                } else {
                    TVMessageView(
                        systemImage: AppSymbol.accounts,
                        title: "No channels yet",
                        message: "Open a channel and choose Follow, or sign in to use your YouTube subscriptions.",
                        actionTitle: "Sign In", action: { showSignIn = true },
                        secondaryTitle: "Find Channels", secondaryAction: { navigator.selection = .search }
                    )
                    .frame(height: 700)
                    .fullScreenCover(isPresented: $showSignIn) { SignInView() }
                }
            }
            .padding(.bottom, 80)
        }
        .task(id: auth.accessToken) {
            let token = auth.accessToken
            if case .some(let started) = startedToken, started == token { return }
            startedToken = .some(token)
            if vm == nil { vm = BrowseViewModel(api: api, initialSection: section) }
            if let vm { await tvStartBrowse(vm, section: section, token: token) }
        }
        // Who's live, each time the page shows (at most every couple of minutes).
        .task(id: auth.accessToken) {
            if auth.isSignedIn, let token = auth.accessToken { await live.refresh(api: api, token: token) }
        }
        .task(id: follows.all.map(\.id)) { await externalLive.refresh(channels: follows.all) }
    }

    private var sortMenu: some View {
        @Bindable var store = store
        return HStack {
            Menu {
                Picker("Sort", selection: $store.settings.channelSort) {
                    ForEach(ChannelSort.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            } label: {
                Label("Sort: \(store.settings.channelSort.title)", systemImage: AppSymbol.sortOrder)
            }
            .accessibilityIdentifier(AccessibilityID.Channels.sortMenu)
            Spacer()
        }
        .padding(.horizontal, TVLayout.pageInset)
        .focusSection()
    }
}
#endif
