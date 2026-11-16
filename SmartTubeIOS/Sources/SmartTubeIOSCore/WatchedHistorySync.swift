import Foundation
import os

private let syncLog = Logger(subsystem: appSubsystem, category: "WatchedHistorySync")

// MARK: - WatchedHistorySync

/// Reads the account's whole YouTube watch history into `WatchedStore`, so every card — a
/// channel's videos, search, Up Next — shows what was watched anywhere, not just what this app
/// played or a History shelf happened to load.
///
/// - The first sync reads the history to its end (the backfill), one page every `pace`, so it
///   looks like someone scrolling History rather than a burst. Where it got to is saved with the
///   account's data, so a relaunch or a later sync carries on; an error stops it until the next.
/// - Once the backfill is done (or while it's parked partway), each sync reads only the newest
///   pages, stopping at the first page that brings nothing new.
///
/// At most one sync every `minimumInterval` per account. An account switch mid-sync stops it
/// before it writes anything.
@MainActor
public final class WatchedHistorySync {
    public static let shared = WatchedHistorySync()

    static let minimumInterval: TimeInterval = 15 * 60
    static let pace: Duration = .seconds(2)
    /// Newest pages read before giving up on reaching known history.
    static let newestPagesLimit = 25
    /// Backfill pages per sync; the rest waits for the next one.
    static let backfillPagesLimit = 300

    private let store: WatchedStore
    private let now: () -> Date
    private let pause: @Sendable (Duration) async -> Void
    private var lastSync: [String: Date] = [:]
    private var running: Task<Void, Never>?

    init(
        store: WatchedStore = .shared, now: @escaping () -> Date = Date.init,
        pause: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) {
        self.store = store
        self.now = now
        self.pause = pause
    }

    /// Starts a sync unless one ran for this account within `minimumInterval` (or is running).
    public func syncIfDue(api: any InnerTubeAPIProtocol) {
        let slot = Self.liveSlot
        guard running == nil else { return }
        if let last = lastSync[slot], now().timeIntervalSince(last) < Self.minimumInterval { return }
        lastSync[slot] = now()
        running = Task { [weak self] in
            await self?.sync(api: api, slot: slot)
            self?.running = nil
        }
    }

    /// Waits for a sync started by `syncIfDue` (tests).
    func finishRunning() async {
        await running?.value
    }

    /// One sync for `slot` (default: the live account); returns the number of pages read.
    @discardableResult
    func sync(api: any InnerTubeAPIProtocol, slot requested: String? = nil) async -> Int {
        let slot = requested ?? Self.liveSlot
        var pages = await readNewest(api: api, slot: slot)
        pages += await continueBackfill(api: api, slot: slot)
        syncLog.notice(
            "history sync: \(pages) pages, \(self.store.entries.count) videos known, backfill complete=\(self.store.backfill.isComplete)"
        )
        return pages
    }

    /// From the top until a page brings nothing new. With no backfill under way, this is where
    /// it starts: every page counts, and each next token is saved as the backfill's position.
    private func readNewest(api: any InnerTubeAPIProtocol, slot: String) async -> Int {
        let startsBackfill = store.backfill == .notStarted
        var token: String?
        var pages = 0
        while pages < (startsBackfill ? Self.backfillPagesLimit : Self.newestPagesLimit) {
            if pages > 0 { await pause(Self.pace) }
            guard let page = try? await api.fetchHistory(continuationToken: token), Self.liveSlot == slot else {
                break
            }
            pages += 1
            let fresh = store.absorbHistory(page.videos)
            let next = page.videos.isEmpty ? nil : page.nextPageToken
            if startsBackfill {
                store.updateBackfill(HistoryBackfill(token: next, isComplete: next == nil || store.isFull))
            }
            guard let next, startsBackfill || fresh > 0 else { break }
            token = next
        }
        return pages
    }

    /// Carries a backfill on from its saved position.
    private func continueBackfill(api: any InnerTubeAPIProtocol, slot: String) async -> Int {
        var pages = 0
        while pages < Self.backfillPagesLimit, !store.backfill.isComplete, let token = store.backfill.token {
            await pause(Self.pace)
            guard Self.liveSlot == slot else { break }
            do {
                let page = try await api.fetchHistory(continuationToken: token)
                guard Self.liveSlot == slot else { break }
                pages += 1
                store.absorbHistory(page.videos)
                let next = page.videos.isEmpty ? nil : page.nextPageToken
                store.updateBackfill(HistoryBackfill(token: next, isComplete: next == nil || store.isFull))
            } catch {
                // Possibly a stale token: start over from the top next time (known pages are
                // cheap — they change nothing). Network trouble just waits for the next sync.
                syncLog.notice("history backfill stopped: \(error.localizedDescription, privacy: .public)")
                if Self.liveSlot == slot { store.updateBackfill(.notStarted) }
                break
            }
        }
        return pages
    }

    private static var liveSlot: String { AccountScope.currentSlot ?? AccountScope.guestSlot }
}
