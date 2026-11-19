import Foundation
import Observation

// MARK: - ExternalLiveStore

/// Followed Twitch and Kick channels that are live now, with their streams, most watched
/// first. Read by the Twitch and Kick tabs and Home's Live Now; refreshed like
/// `SubscriptionLiveStore` (at most once per `freshness`, one read at a time).
@MainActor
@Observable
public final class ExternalLiveStore {
    public static let shared = ExternalLiveStore()

    /// How the live streams are looked up; replaced in tests.
    public struct Sources: Sendable {
        /// Live streams of these Twitch logins (one lookup for up to 100).
        public var twitch: @Sendable ([String]) async -> [Video]
        /// The Kick channel's live stream, nil when offline.
        public var kick: @Sendable (String) async -> Video?

        public static let live = Sources(
            twitch: { logins in
                guard !logins.isEmpty else { return [] }
                return ((try? await TwitchClient.shared.channels(logins: logins)) ?? []).compactMap(\.live)
            },
            kick: { slug in try? await KickClient.shared.livestream(slug: slug) }
        )
    }

    static let freshness: TimeInterval = 120

    public private(set) var videos: [Video] = []
    @ObservationIgnored private let sources: Sources
    @ObservationIgnored private let now: () -> Date
    private var lastRefresh: Date?
    private var lastFollows: Set<String> = []
    private var running: Task<Void, Never>?

    init(sources: Sources = .live, now: @escaping () -> Date = Date.init) {
        self.sources = sources
        self.now = now
    }

    public func videos(_ platform: StreamPlatform) -> [Video] {
        videos.filter { $0.platform == platform }
    }

    /// The channel's live stream, if it's live.
    public func liveVideo(of channelId: String) -> Video? {
        videos.first { $0.channelId == channelId }
    }

    /// Re-reads who's live among `channels` (Twitch and Kick channel ids) unless it was read
    /// within `freshness` for the same channels; a read already under way is waited for.
    public func refresh(channels: [Channel]) async {
        let follows = Set(channels.map(\.id))
        if let running {
            await running.value
            return
        }
        if follows == lastFollows, let lastRefresh, now().timeIntervalSince(lastRefresh) < Self.freshness { return }
        let read = Task { await self.read(channels) }
        running = read
        await read.value
        running = nil
        lastFollows = follows
        lastRefresh = now()
    }

    private func read(_ channels: [Channel]) async {
        let logins = channels.compactMap { channel -> String? in
            guard let parsed = ExternalID.parse(channel.id), parsed.platform == .twitch else { return nil }
            return parsed.key
        }
        let slugs = channels.compactMap { channel -> String? in
            guard let parsed = ExternalID.parse(channel.id), parsed.platform == .kick else { return nil }
            return parsed.key
        }
        let sources = sources
        async let twitch = sources.twitch(logins)
        let kick = await withTaskGroup(of: Video?.self) { group in
            for slug in slugs { group.addTask { await sources.kick(slug) } }
            var found: [Video] = []
            for await video in group { if let video { found.append(video) } }
            return found
        }
        let named = Dictionary(channels.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
        videos = (await twitch + kick)
            .map { video in
                // Kick's live answer has no channel name; the followed channel has it.
                var video = video
                if let name = video.channelId.flatMap({ named[$0] }), video.channelTitle != name {
                    video.channelTitle = name
                }
                return video
            }
            .sorted { ($0.viewCount ?? 0) > ($1.viewCount ?? 0) }
    }
}
