import Foundation
import Observation

// MARK: - ExternalFeedStore

/// The latest past broadcasts of the profile's followed Twitch and Kick channels, newest first —
/// what Subscriptions blends in with the YouTube feed. Refreshed at most once per `freshness`
/// for the same follows, one read at a time; `reset` on a profile switch.
@MainActor
@Observable
public final class ExternalFeedStore {
    public static let shared = ExternalFeedStore()

    /// How a channel's past broadcasts are read (newest first); replaced in tests.
    public struct Sources: Sendable {
        public var twitch: @Sendable (String) async -> [Video]
        public var kick: @Sendable (String) async -> [Video]

        public static let live = Sources(
            twitch: { login in (try? await TwitchClient.shared.videos(login: login).videos) ?? [] },
            kick: { slug in (try? await KickClient.shared.videos(slug: slug)) ?? [] }
        )
    }

    static let freshness: TimeInterval = 10 * 60
    /// Broadcasts kept per channel: a busy streamer doesn't fill the feed.
    nonisolated static let perChannel = 6

    public private(set) var videos: [Video] = []
    @ObservationIgnored private let sources: Sources
    @ObservationIgnored private let now: () -> Date
    private var lastRefresh: Date?
    private var lastFollows: Set<String> = []
    private var running: Task<Void, Never>?
    private var generation = 0

    init(sources: Sources = .live, now: @escaping () -> Date = Date.init) {
        self.sources = sources
        self.now = now
    }

    /// Another profile's follows are coming: nothing of this one's stays on screen.
    public func reset() {
        generation += 1
        running = nil
        videos = []
        lastRefresh = nil
        lastFollows = []
    }

    public func refresh(channels: [Channel]) async {
        let follows = Set(channels.map(\.id))
        if let running {
            await running.value
            return
        }
        if follows == lastFollows, let lastRefresh, now().timeIntervalSince(lastRefresh) < Self.freshness { return }
        let generation = generation
        let read = Task { await self.read(channels, generation: generation) }
        running = read
        await read.value
        guard generation == self.generation else { return }
        running = nil
        lastFollows = follows
        lastRefresh = now()
    }

    /// `videos` blended into a newest-first YouTube feed: the broadcasts no older than the feed's
    /// oldest loaded video (older ones come in as more of the feed loads), or all of them when
    /// the feed is complete or empty.
    public static func blended(_ feed: [Video], with external: [Video], feedIsComplete: Bool) -> [Video] {
        let oldest = feedIsComplete ? nil : feed.compactMap(\.publishedAt).min()
        let shown = external.filter { video in
            guard let oldest else { return true }
            return (video.publishedAt ?? .distantPast) >= oldest
        }
        return CompanionAccounts.mergedFeed([feed, shown])
    }

    private func read(_ channels: [Channel], generation: Int) async {
        let sources = sources
        let named = Dictionary(channels.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
        let found = await withTaskGroup(of: [Video].self) { group in
            for channel in channels {
                guard let parsed = ExternalID.parse(channel.id) else { continue }
                group.addTask {
                    let videos =
                        switch parsed.platform {
                        case .twitch: await sources.twitch(parsed.key)
                        case .kick: await sources.kick(parsed.key)
                        case .youtube: [Video]()
                        }
                    return Array(videos.filter { !$0.isLive }.prefix(Self.perChannel))
                }
            }
            var all: [Video] = []
            for await videos in group { all += videos }
            return all
        }
        guard generation == self.generation else { return }
        videos = CompanionAccounts.mergedFeed([
            found.map { video in
                // The followed channel's name, as the Twitch and Kick tabs show it.
                var video = video
                if let name = video.channelId.flatMap({ named[$0] }), !name.isEmpty { video.channelTitle = name }
                return video
            }
        ])
    }
}
