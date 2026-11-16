import Foundation
import Testing

@testable import SmartTubeIOSCore

@Suite("ContinueWatchingStore — removed videos")
struct ContinueWatchingStoreTests {
    private func makeStore() -> ContinueWatchingStore {
        ContinueWatchingStore(suiteName: "continue-watching-\(UUID().uuidString)")
    }

    @Test func removedVideoStaysOff() async {
        let store = makeStore()
        let watched = Date(timeIntervalSince1970: 1_000)
        await store.remove(videoId: "a", at: watched.addingTimeInterval(60))

        #expect(await store.isRemoved("a", lastWatched: watched))
        #expect(await store.isRemoved("a", lastWatched: nil))
        #expect(await !store.isRemoved("b", lastWatched: watched))
    }

    /// Watching it again (a newer saved position) brings it back.
    @Test func watchingAgainBringsItBack() async {
        let store = makeStore()
        let removedAt = Date(timeIntervalSince1970: 1_000)
        await store.remove(videoId: "a", at: removedAt)

        #expect(await !store.isRemoved("a", lastWatched: removedAt.addingTimeInterval(30)))
    }

    /// The "Continue Watching" shortcut skips removed videos.
    @Test func shortcutOpensTheNewestVideoNotRemoved() async {
        let store = makeStore()
        let states = VideoStateStore(suiteName: "continue-watching-states-\(UUID().uuidString)")
        await store.remove(videoId: "newest")
        let history = [
            Video(id: "newest", title: "", channelTitle: ""), Video(id: "older", title: "", channelTitle: ""),
        ]

        #expect(await store.mostRecent(in: history, videoStates: states)?.id == "older")
        #expect(await store.mostRecent(in: Array(history.prefix(1)), videoStates: states) == nil)
    }

    @Test func removalsSurviveRelaunch() async {
        let suite = "continue-watching-\(UUID().uuidString)"
        await ContinueWatchingStore(suiteName: suite).remove(videoId: "a")

        #expect(await ContinueWatchingStore(suiteName: suite).isRemoved("a", lastWatched: nil))
    }
}
