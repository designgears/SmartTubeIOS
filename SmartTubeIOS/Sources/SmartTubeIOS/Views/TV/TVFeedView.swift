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
    }

    @ViewBuilder private var content: some View {
        let videos = visibleVideos
        if let vm, !videos.isEmpty {
            TVVideoGrid(
                videos: videos,
                onReachEnd: {
                    if let last = vm.videoGroups.last?.videos.last { vm.loadMoreIfNeeded(lastVideo: last) }
                },
                onSelect: { navigator.play($0) }
            )
        } else if vm == nil || vm?.isLoading == true {
            TVLoadingView().frame(height: 700)
        } else if needsSignIn {
            TVSignInPrompt(title: "Sign in to see \(title)", message: signInMessage).frame(height: 700)
        } else if let error = vm?.error {
            TVMessageView(
                systemImage: "exclamationmark.triangle",
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
        let all = (vm?.videoGroups.flatMap(\.videos) ?? []).uniquedByID()
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
    @State private var vm: BrowseViewModel?
    @State private var startedToken: String?? = .none
    @State private var showSignIn = false

    private let section = BrowseSection(type: .channels)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TVPageHeader(title: "Channels", subtitle: auth.isSignedIn ? nil : "Channels you follow on this Apple TV")
                if let vm, !vm.subscribedChannels.isEmpty {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 250, maximum: 290), spacing: 40, alignment: .top)],
                        spacing: 56
                    ) {
                        ForEach(vm.subscribedChannels) { channel in
                            TVChannelCard(
                                title: channel.title,
                                thumbnailURL: channel.thumbnailURL,
                                subtitle: channel.subscriberCount
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
                        systemImage: "person.2",
                        title: "No channels yet",
                        message: "Channels you subscribe to on YouTube appear here.",
                        actionTitle: "Refresh", action: { vm?.reload(section: section) }
                    )
                    .frame(height: 700)
                } else {
                    TVMessageView(
                        systemImage: "person.2",
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
    }
}
#endif
