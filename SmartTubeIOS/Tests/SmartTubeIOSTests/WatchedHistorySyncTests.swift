import Foundation
import Testing

@testable import SmartTubeIOSCore

/// The account's YouTube history read into `WatchedStore`, so cards anywhere (a channel's
/// videos) show what was watched on YouTube, not only what the History shelf loaded.
@Suite("WatchedHistorySync — YouTube history into the watched store")
@MainActor
struct WatchedHistorySyncTests {
    /// A mock answering history pages by continuation token ("" = the first page).
    private func historyAPI(_ pages: [String: VideoGroup]) -> MockInnerTubeAPI {
        let mock = MockInnerTubeAPI()
        mock.historyHandler = { pages[$0 ?? ""] ?? VideoGroup(title: "History", videos: []) }
        return mock
    }

    private func store() -> WatchedStore {
        WatchedStore(
            // swiftlint:disable:next force_unwrapping
            defaults: UserDefaults(suiteName: "history-sync-\(UUID().uuidString)")!,
            directory: FileManager.default.temporaryDirectory.appendingPathComponent("sync-\(UUID().uuidString)"),
            slot: "account")
    }

    private func sync(_ store: WatchedStore, now: @escaping () -> Date = Date.init) -> WatchedHistorySync {
        WatchedHistorySync(store: store, now: now, pause: { _ in })
    }

    private func watched(_ id: String, _ progress: Double) -> Video {
        var video = Video(id: id, title: id, channelTitle: "The B1M")
        video.watchProgress = progress
        return video
    }

    private func page(_ videos: [Video], next: String?) -> VideoGroup {
        VideoGroup(title: "History", videos: videos, nextPageToken: next)
    }

    private var threePages: [String: VideoGroup] {
        [
            "": page([watched("new", 0.5)], next: "p2"),
            "p2": page([watched("older", 1)], next: "p3"),
            "p3": page([watched("oldest", 0.9)], next: nil),
        ]
    }

    @Test func firstSyncReadsTheWholeHistory() async {
        let watchedStore = store()
        #expect(await sync(watchedStore).sync(api: historyAPI(threePages)) == 3)
        #expect(watchedStore.progress(for: Video(id: "oldest", title: "", channelTitle: "")) == 0.9)
        #expect(watchedStore.backfill.isComplete)
    }

    @Test func laterSyncsStopAtThePageWithNothingNew() async {
        let watchedStore = store()
        let history = sync(watchedStore)
        let api = historyAPI(threePages)
        await history.sync(api: api)
        #expect(await history.sync(api: api) == 1)
    }

    /// A backfill parked partway (relaunch, or its page limit): the newest pages first, then on
    /// from where it stopped.
    @Test func resumesAParkedBackfill() async {
        let watchedStore = store()
        watchedStore.absorbHistory([watched("new", 0.5)])
        watchedStore.updateBackfill(HistoryBackfill(token: "p3", isComplete: false))
        let api = historyAPI(threePages)
        #expect(await sync(watchedStore).sync(api: api) == 2)
        #expect(api.calls.map(\.args) == [["nil"], ["p3"]])
        #expect(watchedStore.progress(for: Video(id: "oldest", title: "", channelTitle: "")) == 0.9)
        #expect(watchedStore.backfill.isComplete)
    }

    @Test func throttledPerAccount() async {
        var clock = Date(timeIntervalSince1970: 1_000_000)
        let api = historyAPI(["": page([watched("a", 1)], next: nil)])
        let history = sync(store(), now: { clock })
        history.syncIfDue(api: api)
        await history.finishRunning()
        history.syncIfDue(api: api)
        await history.finishRunning()
        #expect(api.calls.count == 1)
        clock += WatchedHistorySync.minimumInterval + 1
        history.syncIfDue(api: api)
        await history.finishRunning()
        #expect(api.calls.count == 2)
    }
}
