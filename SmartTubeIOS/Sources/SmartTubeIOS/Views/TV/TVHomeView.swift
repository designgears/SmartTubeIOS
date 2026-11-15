#if os(tvOS)
import SmartTubeIOSCore
import SwiftUI

// MARK: - TVHomeView

/// Home: featured hero, then horizontal shelves (Continue Watching, Recommended,
/// Subscriptions, Shorts, and a few Explore categories).
struct TVHomeView: View {
    @Environment(\.innerTubeAPI) private var api
    @Environment(AuthService.self) private var auth
    @Environment(SettingsStore.self) private var store
    @Environment(TVNavigator.self) private var navigator

    /// Signed-in personalised home (recommended + subscriptions + shorts).
    @State private var homeVM: HomeViewModel?
    /// Signed-out fallback feed (popular / trending).
    @State private var popularVM: BrowseViewModel?
    /// Watch history, for Continue Watching (works signed out via local history).
    @State private var historyVM: BrowseViewModel?
    @State private var startedToken: String?? = .none
    @Namespace private var focusNamespace
    /// Locally saved watch fractions for history videos (player checkpoints).
    @State private var localProgress: [String: Double] = [:]
    @State private var playerWasOpen = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: TVLayout.sectionSpacing) {
                // Banner turned off in Settings: nothing at all — no loader, no reserved space;
                // Home starts with the shelves.
                if let hero = heroVideo {
                    TVHeroView(video: hero, focusNamespace: focusNamespace)
                } else if showsHero, isInitialLoading {
                    TVLoadingView().frame(height: 640)
                } else if !hasMainContent, !isInitialLoading {
                    // Feed failed or came back empty: always leave something focusable.
                    TVMessageView(
                        systemImage: AppSymbol.offline,
                        title: "Couldn't load your feed",
                        message: "Check your connection, then try again.",
                        actionTitle: "Try Again"
                    ) {
                        Task {
                            startedToken = .none
                            await start()
                        }
                    }
                    .frame(height: 640)
                }

                if !continueWatching.isEmpty {
                    TVShelf(
                        title: "Continue Watching", items: continueWatching, prefetchWidth: TVLayout.cardWidth
                    ) { video in
                        TVVideoCard(video: video) { navigator.play(video) }
                    }
                }

                if recommended.isEmpty, !showsHero, isInitialLoading {
                    // Without the banner, Recommended loads like any other shelf.
                    TVShelfSkeleton(title: "Recommended")
                }
                if !recommended.isEmpty {
                    TVShelf(
                        title: "Recommended", items: recommended, onReachEnd: loadMoreRecommended,
                        prefetchWidth: TVLayout.cardWidth
                    ) { video in
                        TVVideoCard(video: video) { navigator.play(video) }
                    }
                }

                if !subscriptionVideos.isEmpty {
                    TVShelf(
                        title: "From Your Subscriptions", items: subscriptionVideos, prefetchWidth: TVLayout.cardWidth
                    ) { video in
                        TVVideoCard(video: video) { navigator.play(video) }
                    }
                }

                if !shorts.isEmpty {
                    TVShelf(title: "Shorts", items: shorts) { video in
                        TVShortCard(video: video) { navigator.play(video) }
                    }
                }

                // Explore shelves wait for the main feed so the hero is the first focusable
                // element (otherwise focus lands on whichever shelf loaded first).
                if hasMainContent || !isInitialLoading {
                    TVSectionShelf(type: .music, title: "Music")
                    TVSectionShelf(type: .gaming, title: "Gaming")
                    TVSectionShelf(type: .news, title: "News")
                }

                if !auth.isSignedIn {
                    TVSignInPrompt(
                        title: "Make it yours",
                        message: "Sign in to see your recommendations, subscriptions and watch history."
                    )
                    .frame(height: 560)
                }
            }
            .padding(.bottom, 80)
        }
        // Only the banner runs to the top edge; without it the shelves keep the normal margin.
        .ignoresSafeArea(edges: showsHero ? .top : [])
        .focusScope(focusNamespace)
        .task(id: auth.accessToken) { await start() }
        // After the player closes: refresh history and the local positions so Continue
        // Watching and the progress bars reflect what was just watched.
        .task(id: navigator.nowPlaying == nil) {
            if navigator.nowPlaying != nil {
                playerWasOpen = true
                return
            }
            guard playerWasOpen else { return }
            playerWasOpen = false
            // In place: Continue Watching keeps its cards until the refreshed list arrives.
            historyVM?.refreshInPlace()
        }
        .task(id: historyVM?.videoGroups.flatMap(\.videos).map(\.id) ?? []) {
            var fractions: [String: Double] = [:]
            for video in historyVM?.videoGroups.flatMap(\.videos) ?? [] {
                if let fraction = await VideoStateStore.shared.state(for: video.id)?.watchedFraction {
                    fractions[video.id] = fraction
                }
            }
            localProgress = fractions
        }
        // Seed the playback session as soon as there is something to play, so the first
        // Play doesn't wait on the watch-page round-trip.
        .task(id: recommendedAll.first?.id) {
            guard let id = recommendedAll.first?.id else { return }
            await api.warmVisionOSSession(videoId: id)
        }
    }

    // MARK: Data

    private var isSignedIn: Bool { auth.isSignedIn && auth.accessToken != nil }

    private var hideShorts: Bool { store.settings.hideShorts }

    private var recommendedAll: [Video] {
        let source = isSignedIn ? (homeVM?.homeRegularVideos ?? []) : (popularVM?.videoGroups.flatMap(\.videos) ?? [])
        return source.filter { !$0.isShort }.uniquedByID()
    }

    private var showsHero: Bool { store.settings.showHomeHero }

    private var heroVideo: Video? { showsHero ? recommendedAll.first : nil }

    /// With the banner on, its video is not repeated in the Recommended shelf.
    private var recommended: [Video] { showsHero ? Array(recommendedAll.dropFirst()) : recommendedAll }

    /// The main feed has produced something to show (banner or Recommended shelf).
    private var hasMainContent: Bool { heroVideo != nil || !recommended.isEmpty }

    private var subscriptionVideos: [Video] {
        guard isSignedIn else { return [] }
        let subs = homeVM?.sections.first { $0.section.type == .subscriptions }?.videos ?? []
        return Array(subs.filter { !$0.isShort }.uniquedByID().prefix(30))
    }

    private var shorts: [Video] {
        guard !hideShorts, isSignedIn else { return [] }
        return Array((homeVM?.homeShortsVideos ?? []).uniquedByID().prefix(30))
    }

    private var continueWatching: [Video] {
        let videos = historyVM?.videoGroups.flatMap(\.videos) ?? []
        return Array(
            videos.filter { video in
                let fraction = localProgress[video.id] ?? video.watchProgress ?? 0
                return fraction > 0.03 && fraction < 0.95 && !video.isShort
            }
            .uniquedByID()
            .prefix(20))
    }

    private var isInitialLoading: Bool {
        if isSignedIn { return homeVM?.isLoadingAny ?? true }
        return popularVM?.isLoading ?? true
    }

    private func loadMoreRecommended() {
        if isSignedIn {
            homeVM?.loadMoreMerged()
        } else if let vm = popularVM, let last = vm.videoGroups.last?.videos.last {
            vm.loadMoreIfNeeded(lastVideo: last)
        }
    }

    private func start() async {
        let token = auth.accessToken
        if case .some(let started) = startedToken, started == token { return }
        startedToken = .some(token)

        if historyVM == nil {
            historyVM = BrowseViewModel(api: api, initialSection: BrowseSection(type: .history))
        }
        if let token {
            if homeVM == nil { homeVM = HomeViewModel(api: api) }
            await homeVM?.updateAuthToken(token)
            if homeVM?.mergedVideos.isEmpty == true, homeVM?.isLoadingAny == false { homeVM?.load() }
            await historyVM?.updateAuthToken(token)
        } else {
            if popularVM == nil {
                popularVM = BrowseViewModel(api: api, initialSection: BrowseSection(type: .recommended))
            }
            popularVM?.reload(section: BrowseSection(type: .recommended))
            historyVM?.reload(section: BrowseSection(type: .history))
        }
    }
}

// MARK: - Hero

struct TVHeroView: View {
    let video: Video
    var focusNamespace: Namespace.ID?
    @Environment(TVNavigator.self) private var navigator

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            TVRemoteImage(
                urls: [video.maxResThumbnailURL].compactMap { $0 } + video.highResThumbnailFallbackURLs,
                pointWidth: 1920
            )
            .frame(maxWidth: .infinity)
            .frame(height: 760)
            .overlay {
                LinearGradient(
                    colors: [.clear, .black.opacity(0.55), .black.opacity(0.95)],
                    startPoint: .top, endPoint: .bottom)
            }
            .overlay {
                LinearGradient(
                    colors: [.black.opacity(0.75), .clear],
                    startPoint: .leading, endPoint: .center)
            }

            VStack(alignment: .leading, spacing: 18) {
                Text(video.channelTitle.uppercased())
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.75))
                Text(video.deArrowTitle ?? video.title)
                    .font(.system(size: 60, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .frame(maxWidth: 1150, alignment: .leading)
                if !meta.isEmpty {
                    Text(meta).font(.headline).foregroundStyle(.white.opacity(0.75))
                }
                HStack(spacing: 28) {
                    Button {
                        navigator.play(video)
                    } label: {
                        Label("Play", systemImage: AppSymbol.play).padding(.horizontal, 24)
                    }
                    .modifier(TVDefaultFocus(namespace: focusNamespace))
                    if video.channelId != nil {
                        Button {
                            navigator.openChannel(of: video)
                        } label: {
                            Label("Channel", systemImage: AppSymbol.personSquare)
                        }
                    }
                }
                .padding(.top, 10)
            }
            .padding(.horizontal, TVLayout.pageInset)
            .padding(.bottom, 64)
        }
        .frame(height: 760)
        .focusSection()
    }

    private var meta: String {
        var parts: [String] = []
        if video.viewCount != nil { parts.append(video.formattedViewCount) }
        if let published = video.publishedTimeText, !published.isEmpty { parts.append(published) }
        if !video.isLive, video.duration != nil { parts.append(video.formattedDuration) }
        if video.isLive { parts.append("LIVE") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Self-loading section shelf

/// A shelf backed by its own `BrowseViewModel` for one section type. Loads lazily the
/// first time it appears (inside a LazyVStack, i.e. when scrolled near).
struct TVSectionShelf: View {
    let type: BrowseSection.SectionType
    let title: String

    @Environment(\.innerTubeAPI) private var api
    @Environment(TVNavigator.self) private var navigator
    @State private var vm: BrowseViewModel?

    var body: some View {
        let videos = (vm?.videoGroups.flatMap(\.videos) ?? []).filter { !$0.isShort }.uniquedByID()
        Group {
            if videos.isEmpty, vm == nil || vm?.isLoading == true {
                // Same footprint as the loaded shelf, so nothing jumps when it arrives.
                TVShelfSkeleton(title: title)
            } else if videos.isEmpty {
                // Loaded but empty: collapse.
                Color.clear.frame(height: 1)
            } else {
                TVShelf(
                    title: title, items: Array(videos.prefix(40)),
                    onReachEnd: {
                        if let vm, let last = vm.videoGroups.last?.videos.last { vm.loadMoreIfNeeded(lastVideo: last) }
                    },
                    prefetchWidth: TVLayout.cardWidth,
                    card: { video in TVVideoCard(video: video) { navigator.play(video) } }
                )
            }
        }
        .onAppear {
            guard vm == nil else { return }
            let section = BrowseSection(type: type)
            let model = BrowseViewModel(api: api, initialSection: section)
            vm = model
            model.reload(section: section)
        }
    }
}
#endif

#if os(tvOS)
/// Marks a control as the preferred default focus inside `namespace` (no-op when nil).
struct TVDefaultFocus: ViewModifier {
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let namespace {
            content.prefersDefaultFocus(true, in: namespace)
        } else {
            content
        }
    }
}
#endif
