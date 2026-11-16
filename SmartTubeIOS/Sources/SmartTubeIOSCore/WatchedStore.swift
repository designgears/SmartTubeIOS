import Foundation
import Observation

// MARK: - WatchedPolicy

/// When a video counts as watched — for dimming it, hiding it from feeds and skipping it
/// when the next video is picked (Settings › Watched Videos).
public struct WatchedPolicy: Sendable, Equatable {
    /// Share of a video that has to have been seen (0.5…1.0).
    public var threshold: Double
    /// Music and music videos are replayed on purpose, so they only count when this is on.
    public var includesMusic: Bool
    /// Also trust YouTube's own progress (feeds' resume bars, the account's watch history).
    public var usesYouTubeHistory: Bool

    public init(threshold: Double, includesMusic: Bool, usesYouTubeHistory: Bool) {
        self.threshold = threshold
        self.includesMusic = includesMusic
        self.usesYouTubeHistory = usesYouTubeHistory
    }

    public init(settings: AppSettings) {
        self.init(
            threshold: settings.hideWatchedThreshold, includesMusic: settings.watchedIncludesMusic,
            usesYouTubeHistory: settings.watchedUsesYouTubeHistory)
    }

    /// `localFraction` is how much was watched in this app; `historyFraction` what YouTube's
    /// history reported. The item's own `watchProgress` (a feed's resume bar) counts as YouTube's.
    public func isWatched(_ video: Video, localFraction: Double?, historyFraction: Double? = nil) -> Bool {
        if !includesMusic, video.looksLikeMusic { return false }
        var seen = localFraction ?? 0
        if usesYouTubeHistory {
            seen = max(seen, historyFraction ?? 0, video.watchProgress ?? 0)
        }
        return seen >= threshold
    }
}

extension Video {
    /// Music by its channel or title (VEVO, "- Topic", "(Official Music Video)"…), the same
    /// signals the player uses when it has nothing better.
    public var looksLikeMusic: Bool {
        PlayerInfo.looksLikeMusic(musicVideoType: nil, category: nil, channelTitle: channelTitle, title: title)
    }
}

// MARK: - WatchedStore

/// How much of each video this profile has seen: the most watched here (kept past the end,
/// which `VideoStateStore` forgets) and the progress YouTube's watch history reports. Per
/// account — swapped by `AccountScope`.
@MainActor
@Observable
public final class WatchedStore {
    public static let shared = WatchedStore()

    struct Entry: Codable, Equatable {
        var local: Double?
        var history: Double?
    }

    static let defaultsKey = "st_watched"
    static let maxEntries = 3_000

    private(set) var entries: [String: Entry] = [:]
    /// Ids oldest-first, for dropping the oldest beyond `maxEntries`.
    @ObservationIgnored private var order: [String] = []
    @ObservationIgnored private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load(defaults.data(forKey: Self.defaultsKey))
    }

    // MARK: Reading

    public func isWatched(_ video: Video, policy: WatchedPolicy) -> Bool {
        let entry = entries[video.id]
        return policy.isWatched(video, localFraction: entry?.local, historyFraction: entry?.history)
    }

    /// `videos` without the watched ones, in order.
    public func unwatched(_ videos: [Video], policy: WatchedPolicy) -> [Video] {
        videos.filter { !isWatched($0, policy: policy) }
    }

    // MARK: Recording

    /// A playback checkpoint: keeps the furthest point reached.
    public func record(videoId: String, position: TimeInterval, duration: TimeInterval) {
        guard duration > 1, position > 0 else { return }
        let fraction = min(position / duration, 1)
        guard fraction > (entries[videoId]?.local ?? 0) else { return }
        update(videoId) { $0.local = fraction }
        persist()
    }

    /// YouTube's progress for videos in the account's watch history.
    public func absorbHistory(_ videos: [Video]) {
        var changed = false
        for video in videos {
            guard let progress = video.watchProgress, progress > 0, progress != entries[video.id]?.history else {
                continue
            }
            update(video.id) { $0.history = progress }
            changed = true
        }
        if changed { persist() }
    }

    // MARK: Accounts

    /// Account switch (see `AccountScope`): park the live data, load the incoming account's.
    public func switchAccountData(from outgoing: String?, to incoming: String) {
        let saved = AccountScope.exchange(
            key: Self.defaultsKey, current: encoded(), outgoing: outgoing, incoming: incoming, defaults: defaults)
        load(saved as? Data)
        persist()
    }

    // MARK: Storage

    private struct Stored: Codable {
        var id: String
        var entry: Entry
    }

    private func update(_ videoId: String, _ change: (inout Entry) -> Void) {
        var entry = entries[videoId] ?? Entry()
        change(&entry)
        if entries[videoId] == nil { order.append(videoId) }
        entries[videoId] = entry
        if order.count > Self.maxEntries {
            let dropped = order.prefix(order.count - Self.maxEntries)
            dropped.forEach { entries.removeValue(forKey: $0) }
            order.removeFirst(dropped.count)
        }
    }

    private func encoded() -> Data? {
        try? JSONEncoder().encode(order.compactMap { id in entries[id].map { Stored(id: id, entry: $0) } })
    }

    private func load(_ data: Data?) {
        let stored = data.flatMap { try? JSONDecoder().decode([Stored].self, from: $0) } ?? []
        entries = Dictionary(stored.map { ($0.id, $0.entry) }, uniquingKeysWith: { _, last in last })
        order = stored.map(\.id)
    }

    private func persist() {
        if let data = encoded() { defaults.set(data, forKey: Self.defaultsKey) }
    }
}

// MARK: - Where watched videos are hidden

extension AppSettings {
    /// Feeds that leave watched videos out when Hide in Feeds is on. Not History or Watch Later
    /// (watched or chosen on purpose), playlists (played in order), or Music (replayed).
    static let feedsHidingWatched: Set<BrowseSection.SectionType> = [
        .home, .recommended, .subscriptions, .shorts, .news, .gaming, .live, .sports,
    ]

    public func hidesWatched(in section: BrowseSection.SectionType) -> Bool {
        hideWatchedInFeeds && Self.feedsHidingWatched.contains(section)
    }

    public var watchedPolicy: WatchedPolicy { WatchedPolicy(settings: self) }
}

extension Array where Element == Video {
    /// Without the watched videos, when `settings` hide them in `section`.
    @MainActor
    public func hidingWatched(in section: BrowseSection.SectionType, settings: AppSettings) -> [Video] {
        guard settings.hidesWatched(in: section) else { return self }
        return WatchedStore.shared.unwatched(self, policy: settings.watchedPolicy)
    }
}
