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
/// account — swapped by `AccountScope` — and kept in a file per account (`WatchedStoreFile`).
@MainActor
@Observable
public final class WatchedStore {
    public static let shared = WatchedStore()

    struct Entry: Codable, Equatable {
        var local: Double?
        var history: Double?
    }

    /// Where this data lived in UserDefaults before it moved to a file (migrated on load).
    static let legacyDefaultsKey = "st_watched"
    /// Enough for a long YouTube history; the oldest entries go beyond it.
    static let maxEntries = 60_000
    /// Coalesces the writes of a run of changes (history pages, playback checkpoints).
    static let writeDelay: Duration = .seconds(2)

    private(set) var entries: [String: Entry] = [:]
    /// The account's full-history read (`WatchedHistorySync`).
    public private(set) var backfill = HistoryBackfill.notStarted
    /// Ids oldest-first, for dropping the oldest beyond `maxEntries`.
    @ObservationIgnored private var order: [String] = []
    /// Whose data is live (an `AccountScope` slot); nil before the first account activation.
    @ObservationIgnored private var slot: String?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let file: WatchedStoreFile
    @ObservationIgnored private var pendingWrite: Task<Void, Never>?

    public init(
        defaults: UserDefaults = .standard, directory: URL? = nil,
        slot: String? = AccountScope.currentSlot
    ) {
        self.defaults = defaults
        self.file = WatchedStoreFile(directory: directory ?? WatchedStoreFile.defaultDirectory)
        self.slot = slot
        if let slot { load(slot, isLive: true) }
    }

    public var isFull: Bool { entries.count >= Self.maxEntries }

    // MARK: Reading

    public func isWatched(_ video: Video, policy: WatchedPolicy) -> Bool {
        let entry = entries[video.id]
        return policy.isWatched(video, localFraction: entry?.local, historyFraction: entry?.history)
    }

    /// The most of `video` seen — here, in the account's history, or on the item's own resume
    /// bar — for the bar on its card. Nil when nothing has been seen.
    public func progress(for video: Video) -> Double? {
        let entry = entries[video.id]
        let seen = [entry?.local, entry?.history, video.watchProgress].compactMap { $0 }.max() ?? 0
        return seen > 0 ? min(seen, 1) : nil
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
        scheduleWrite()
    }

    /// Videos from the account's watch history, with YouTube's progress where it shows one.
    /// Returns how many were new or changed — zero once the history reaches what's known.
    @discardableResult
    public func absorbHistory(_ videos: [Video]) -> Int {
        var changed = 0
        for video in videos {
            // No resume bar (some live streams, Shorts): known, with nothing seen to show.
            let progress = video.watchProgress ?? 0
            let known = entries[video.id]?.history
            guard known == nil || (progress > 0 && progress != known) else { continue }
            update(video.id) { $0.history = progress }
            changed += 1
        }
        if changed > 0 { scheduleWrite() }
        return changed
    }

    func updateBackfill(_ progress: HistoryBackfill) {
        guard progress != backfill else { return }
        backfill = progress
        scheduleWrite()
    }

    // MARK: Accounts

    /// Account switch (see `AccountScope`): save the live data, load the incoming account's.
    /// From no account (first run) the live data isn't anybody's, so it's dropped.
    public func switchAccountData(from outgoing: String?, to incoming: String) {
        if let outgoing {
            slot = outgoing
            flush()
        }
        pendingWrite?.cancel()
        slot = incoming
        load(incoming, isLive: false)
    }

    /// A removed account's data (see `AccountScope.forget`).
    public func forget(accountId: String) {
        file.remove(accountId: accountId, keeping: slot)
    }

    // MARK: Storage

    /// Writes now rather than after `writeDelay` (account switch, tests).
    public func flush() {
        pendingWrite?.cancel()
        pendingWrite = nil
        guard let slot else { return }
        file.write(contents(), for: slot)
    }

    private func scheduleWrite() {
        guard pendingWrite == nil else { return }
        pendingWrite = Task { [weak self] in
            try? await Task.sleep(for: Self.writeDelay)
            guard !Task.isCancelled else { return }
            self?.flush()
        }
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

    private func contents() -> WatchedStoreFile.Contents {
        var contents = WatchedStoreFile.Contents(backfill: backfill)
        for id in order {
            guard let entry = entries[id] else { continue }
            contents.ids.append(id)
            contents.local.append(entry.local)
            contents.history.append(entry.history)
        }
        return contents
    }

    private func load(_ slot: String, isLive: Bool) {
        let contents = file.read(slot) ?? migrateLegacy(slot, isLive: isLive) ?? WatchedStoreFile.Contents()
        var loaded: [String: Entry] = [:]
        var ids: [String] = []
        for (index, id) in contents.ids.enumerated() where loaded[id] == nil {
            loaded[id] = Entry(
                local: contents.local.indices.contains(index) ? contents.local[index] : nil,
                history: contents.history.indices.contains(index) ? contents.history[index] : nil)
            ids.append(id)
        }
        entries = loaded
        order = ids
        backfill = contents.backfill
    }

    /// Data saved before the file: a parked account's under its `AccountScope` slot key, and
    /// the account live at launch under the plain key. Moved into the file, then removed.
    private func migrateLegacy(_ slot: String, isLive: Bool) -> WatchedStoreFile.Contents? {
        struct Stored: Codable {
            var id: String
            var entry: Entry
        }
        let parkedKey = AccountScope.slotKey(Self.legacyDefaultsKey, slot: slot)
        let key = defaults.data(forKey: parkedKey) != nil || !isLive ? parkedKey : Self.legacyDefaultsKey
        guard let data = defaults.data(forKey: key),
            let stored = try? JSONDecoder().decode([Stored].self, from: data)
        else { return nil }
        var contents = WatchedStoreFile.Contents()
        for item in stored {
            contents.ids.append(item.id)
            contents.local.append(item.entry.local)
            contents.history.append(item.entry.history)
        }
        file.write(contents, for: slot)
        defaults.removeObject(forKey: key)
        return contents
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
