#if os(tvOS)
import SmartTubeIOSCore
import SwiftUI

// MARK: - TVStreamingView

/// The Twitch or Kick tab: followed channels that are live, every followed channel, search.
struct TVStreamingView: View {
    let platform: StreamPlatform

    @Environment(TVNavigator.self) private var navigator
    private var follows: ExternalFollowStore { .shared }
    private var live: ExternalLiveStore { .shared }

    /// Live channels first, then by name.
    private var followed: [Channel] {
        follows.channels(platform).sorted { lhs, rhs in
            let (lhsLive, rhsLive) = (live.liveVideo(of: lhs.id) != nil, live.liveVideo(of: rhs.id) != nil)
            if lhsLive != rhsLive { return lhsLive }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TVLayout.sectionSpacing) {
                VStack(alignment: .leading, spacing: 20) {
                    TVPageHeader(title: platform.title, subtitle: "Channels you follow on this Apple TV")
                    HStack {
                        Button {
                            navigator.open(.streamingSearch(platform))
                        } label: {
                            Label("Search \(platform.title)", systemImage: AppSymbol.search)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, TVLayout.pageInset)
                    .focusSection()
                }
                let liveNow = live.videos(platform)
                if !liveNow.isEmpty {
                    TVShelf(title: "Live Now", items: liveNow, prefetchWidth: TVLayout.cardWidth) { video in
                        TVVideoCard(video: video) { navigator.play(video) }
                    }
                }
                if followed.isEmpty {
                    TVMessageView(
                        systemImage: platform == .twitch ? AppSymbol.twitch : AppSymbol.kick,
                        title: "No channels yet",
                        message: "Search for \(platform.title) channels and follow them to see when they're live.",
                        actionTitle: "Search", action: { navigator.open(.streamingSearch(platform)) }
                    )
                    .frame(height: 500)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Following")
                            .font(.title3.weight(.bold))
                            .padding(.leading, TVLayout.pageInset)
                        TVStreamingChannelGrid(channels: followed)
                    }
                }
            }
            .padding(.bottom, 80)
        }
        // Who's live: when the tab shows (at most every couple of minutes) and right after a
        // follow or unfollow (coming back from a channel page doesn't show the tab again).
        .task(id: follows.all.map(\.id)) { await live.refresh(channels: follows.all) }
    }
}

// MARK: - TVStreamingChannelGrid

/// Channel avatars; a live channel has its ring and LIVE tag.
struct TVStreamingChannelGrid: View {
    let channels: [Channel]
    /// Live state from a search answer, for channels the live store doesn't follow.
    var liveIds: Set<String> = []

    @Environment(TVNavigator.self) private var navigator

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 250, maximum: 290), spacing: 40, alignment: .top)],
            spacing: 56
        ) {
            ForEach(channels, id: \.id) { channel in
                TVChannelCard(
                    title: channel.title,
                    thumbnailURL: channel.thumbnailURL,
                    subtitle: channel.subscriberCount,
                    isLive: liveIds.contains(channel.id) || ExternalLiveStore.shared.liveVideo(of: channel.id) != nil
                ) {
                    navigator.open(.channel(id: channel.id, title: channel.title))
                }
            }
        }
        .padding(.horizontal, TVLayout.pageInset)
        .padding(.vertical, 24)
        .focusSection()
    }
}

// MARK: - TVStreamingSearchView

/// Search Twitch or Kick channels, to watch or follow.
struct TVStreamingSearchView: View {
    let platform: StreamPlatform

    @State private var text = ""
    @State private var results: [ExternalChannel] = []
    @State private var searched = false
    @State private var failure: String?

    static let typingPause: Duration = .milliseconds(450)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !results.isEmpty {
                    TVStreamingChannelGrid(
                        channels: results.map(\.channel),
                        liveIds: Set(results.filter { $0.live != nil }.map(\.id)))
                } else if let failure {
                    TVMessageView(systemImage: AppSymbol.warningOutline, title: "Couldn't search", message: failure)
                        .frame(height: 400)
                } else if searched {
                    TVMessageView(
                        systemImage: AppSymbol.search, title: "No channels found",
                        message: "Try another name."
                    )
                    .frame(height: 400)
                }
            }
            .padding(.bottom, 80)
        }
        .searchable(text: $text, prompt: "Search \(platform.title)")
        .task(id: text) {
            let query = text.trimmingCharacters(in: .whitespaces)
            guard !query.isEmpty else {
                results = []
                searched = false
                return
            }
            try? await Task.sleep(for: Self.typingPause)
            guard !Task.isCancelled else { return }
            do {
                let found =
                    switch platform {
                    case .twitch: try await TwitchClient.shared.search(query)
                    case .kick: try await KickClient.shared.search(query)
                    case .youtube: [ExternalChannel]()
                    }
                guard !Task.isCancelled else { return }
                results = found
                failure = nil
            } catch {
                guard !Task.isCancelled else { return }
                failure = error.localizedDescription
            }
            searched = true
        }
    }
}

// MARK: - TVStreamingChannelView

/// A Twitch or Kick channel: its live stream (focused when live), past broadcasts, Follow.
struct TVStreamingChannelView: View {
    let channelId: String
    let title: String

    @Environment(TVNavigator.self) private var navigator
    @State private var channel: ExternalChannel?
    @State private var videos: [Video] = []
    @State private var cursor: String?
    @State private var isLoading = true
    @State private var failure: String?
    @FocusState private var focusedLive: String?
    @Namespace private var focusNamespace
    @Environment(\.resetFocus) private var resetFocus

    private var target: ExternalID.Parsed? { ExternalID.parse(channelId) }
    private var follows: ExternalFollowStore { .shared }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TVLayout.sectionSpacing) {
                header
                if let live = channel?.live {
                    TVShelf(title: "Live", items: [live], prefetchWidth: TVLayout.cardWidth) { video in
                        TVVideoCard(video: video, focus: $focusedLive) { navigator.play(video) }
                    }
                }
                if !videos.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Past Broadcasts")
                            .font(.title3.weight(.bold))
                            .padding(.leading, TVLayout.pageInset)
                        TVVideoGrid(
                            videos: videos.uniquedByID(), onReachEnd: loadMore, pageKey: videos.count,
                            onSelect: { navigator.play($0) })
                    }
                } else if isLoading {
                    TVLoadingView().frame(height: 500)
                } else if let failure {
                    TVMessageView(
                        systemImage: AppSymbol.warningOutline, title: "Couldn't load this channel", message: failure,
                        actionTitle: "Try Again"
                    ) { Task { await load() } }
                    .frame(height: 500)
                } else if channel?.live == nil {
                    TVMessageView(
                        systemImage: AppSymbol.playRectangle, title: "Nothing to watch",
                        message: "This channel isn't live and has no past broadcasts."
                    )
                    .frame(height: 500)
                }
            }
            .padding(.bottom, 80)
        }
        // A live channel opens on its stream (see TVChannelView).
        .focusScope(focusNamespace)
        .defaultFocus($focusedLive, channel?.live?.id)
        .onChange(of: channel?.live?.id) { _, liveId in
            if liveId != nil { resetFocus(in: focusNamespace) }
        }
        .task { await load() }
    }

    private var header: some View {
        let info = channel?.channel
        let isFollowing = follows.isFollowing(channelId)
        return HStack(alignment: .center, spacing: 48) {
            AsyncImage(url: info?.thumbnailURL) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    ZStack {
                        Color.white.opacity(0.08)
                        Image(systemName: AppSymbol.person).font(.system(size: 80)).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 220, height: 220)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 20) {
                    Text(info?.title ?? title)
                        .font(.system(size: 56, weight: .bold))
                        .lineLimit(1)
                    if let platform = target?.platform { TVPlatformBadge(platform: platform) }
                }
                if let followers = info?.subscriberCount {
                    Text(followers).font(.headline).foregroundStyle(.secondary)
                }
                if let description = info?.description, !description.isEmpty {
                    Text(description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: 1100, alignment: .leading)
                }
                if let info {
                    Button {
                        if isFollowing { follows.unfollow(channelId) } else { follows.follow(info) }
                    } label: {
                        Label(isFollowing ? "Following" : "Follow", systemImage: isFollowing ? "checkmark" : "plus")
                    }
                    .padding(.top, 8)
                }
            }
            Spacer()
        }
        .padding(.horizontal, TVLayout.pageInset)
        .padding(.top, 40)
        .focusSection()
    }

    private func load() async {
        guard let target else { return }
        isLoading = true
        failure = nil
        do {
            switch target.platform {
            case .twitch:
                async let page = TwitchClient.shared.videos(login: target.key)
                channel = try await TwitchClient.shared.channel(login: target.key)
                let first = try await page
                videos = first.videos
                cursor = first.cursor
            case .kick:
                async let past = KickClient.shared.videos(slug: target.key)
                channel = try await KickClient.shared.channel(slug: target.key)
                videos = try await past
                cursor = nil
            case .youtube:
                break
            }
            if let info = channel?.channel {
                follows.update(info)
                // Kick's video list names the channel by its slug.
                videos = videos.map { video in
                    var video = video
                    video.channelTitle = info.title
                    return video
                }
            }
        } catch {
            failure = error.localizedDescription
        }
        isLoading = false
    }

    private func loadMore() {
        guard let target, target.platform == .twitch, let cursor else { return }
        self.cursor = nil
        Task {
            guard let next = try? await TwitchClient.shared.videos(login: target.key, after: cursor) else { return }
            videos += next.videos
            self.cursor = next.cursor
        }
    }
}
#endif
