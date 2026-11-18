import Foundation
import Observation

// MARK: - SubscriptionLiveStore

/// The subscribed channels streaming right now, with their streams: the live tiles in the first
/// `pages` pages of the subscription feed. Home's Live Now shelf and the live channels on
/// Channels read it.
///
/// YouTube places a stream in the feed by when it started, so one that has been running for
/// days can sit past those pages.
@MainActor
@Observable
public final class SubscriptionLiveStore {
    public static let shared = SubscriptionLiveStore()

    /// Feed pages read per refresh.
    static let pages = 3
    /// A refresh this soon after the last one is skipped.
    static let freshness: TimeInterval = 120

    /// The live streams, in feed order.
    public private(set) var videos: [Video] = []
    private var slot: String?
    private var lastRefresh: Date?
    /// The read under way. The store owns it, so a screen that stops waiting (its task
    /// restarted when the token refreshed, or it went away) doesn't cancel it.
    private var running: Task<Void, Never>?
    @ObservationIgnored private let now: () -> Date

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    /// Re-reads the feed unless it was read within `freshness`; with a read already under way,
    /// waits for that one. Another account's streams are dropped first; a failed first page
    /// keeps what's shown until the next try.
    ///
    /// Takes the account's token and hands it to `api` first: the shared API may not have it
    /// yet when a screen asks right at launch, and a signed-out read is an empty feed.
    public func refresh(api: any InnerTubeAPIProtocol, token: String) async {
        let current = Self.liveSlot
        if slot != current {
            slot = current
            videos = []
            lastRefresh = nil
        }
        if let running {
            await running.value
            return
        }
        if let lastRefresh, now().timeIntervalSince(lastRefresh) < Self.freshness { return }
        let read = Task { await self.read(api: api, token: token, slot: current) }
        running = read
        await read.value
        running = nil
    }

    private func read(api: any InnerTubeAPIProtocol, token: String, slot: String) async {
        await api.setAuthToken(token)
        var found: [Video] = []
        var pageToken: String?
        for page in 0..<Self.pages {
            guard let group = try? await api.fetchSubscriptions(continuationToken: pageToken) else {
                if page == 0 { return }
                break
            }
            found += group.videos.filter(\.isLive)
            guard let next = group.nextPageToken, !group.videos.isEmpty else { break }
            pageToken = next
        }
        guard Self.liveSlot == slot else { return }
        lastRefresh = now()
        var seen = Set<String>()
        videos = found.filter { seen.insert($0.id).inserted }
    }

    /// The channel's stream, if it's live. Feed tiles name a channel by `UC…` ID or `@handle`,
    /// so the name is matched too.
    public func liveVideo(of channel: Channel) -> Video? {
        let title = channel.title.lowercased()
        return videos.first { video in
            video.channelId == channel.id || (!title.isEmpty && video.channelTitle.lowercased() == title)
        }
    }

    public func isLive(_ channel: Channel) -> Bool {
        liveVideo(of: channel) != nil
    }

    private static var liveSlot: String { AccountScope.currentSlot ?? AccountScope.guestSlot }
}
