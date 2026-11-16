import Foundation
import Testing

@testable import SmartTubeIOSCore

// MARK: - WatchedPolicy

@Suite("WatchedPolicy — when a video counts as watched")
struct WatchedPolicyTests {
    private let policy = WatchedPolicy(threshold: 0.9, includesMusic: false, usesYouTubeHistory: true)

    private func video(_ progress: Double? = nil, channel: String = "Channel", title: String = "Video") -> Video {
        Video(id: "v", title: title, channelTitle: channel, watchProgress: progress)
    }

    @Test func nothingSeenIsNotWatched() {
        #expect(!policy.isWatched(video(), localFraction: nil))
    }

    @Test func watchedHereCounts() {
        #expect(policy.isWatched(video(), localFraction: 0.92))
        #expect(!policy.isWatched(video(), localFraction: 0.5))
    }

    @Test func youTubeProgressCountsWhenUsed() {
        #expect(policy.isWatched(video(0.95), localFraction: nil))
        #expect(policy.isWatched(video(), localFraction: nil, historyFraction: 1))
        let localOnly = WatchedPolicy(threshold: 0.9, includesMusic: false, usesYouTubeHistory: false)
        #expect(!localOnly.isWatched(video(0.95), localFraction: nil, historyFraction: 1))
        #expect(localOnly.isWatched(video(0.95), localFraction: 0.95))
    }

    /// Music is replayed on purpose — never watched unless included.
    @Test func musicIsLeftAlone() {
        let vevo = video(channel: "TheWeekndVEVO")
        let topic = video(channel: "Shakira - Topic")
        let tagged = video(title: "Dai Dai (Official Music Video)")
        for song in [vevo, topic, tagged] {
            #expect(!policy.isWatched(song, localFraction: 1))
        }
        let withMusic = WatchedPolicy(threshold: 0.9, includesMusic: true, usesYouTubeHistory: true)
        #expect(withMusic.isWatched(vevo, localFraction: 1))
    }

    @Test func lowerThresholdCountsMore() {
        let lenient = WatchedPolicy(threshold: 0.5, includesMusic: false, usesYouTubeHistory: true)
        #expect(lenient.isWatched(video(0.6), localFraction: nil))
        #expect(!policy.isWatched(video(0.6), localFraction: nil))
    }
}

// MARK: - WatchedStore

@MainActor
@Suite("WatchedStore — what this profile has seen")
struct WatchedStoreTests {
    private let policy = WatchedPolicy(threshold: 0.9, includesMusic: false, usesYouTubeHistory: true)

    private struct Place {
        // swiftlint:disable:next force_unwrapping
        let defaults = UserDefaults(suiteName: "watched-\(UUID().uuidString)")!  // a fresh suite name always works
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("watched-\(UUID().uuidString)")

        @MainActor func store(slot: String = "A") -> WatchedStore {
            WatchedStore(defaults: defaults, directory: directory, slot: slot)
        }
    }

    private func makeStore() -> (WatchedStore, Place) {
        let place = Place()
        return (place.store(), place)
    }

    private func video(_ id: String) -> Video { Video(id: id, title: id, channelTitle: "Channel") }

    /// VideoStateStore forgets a video near its end; this keeps the furthest point reached.
    @Test func keepsTheFurthestPoint() {
        let (store, _) = makeStore()
        store.record(videoId: "a", position: 590, duration: 600)
        store.record(videoId: "a", position: 30, duration: 600)  // rewatching the start
        #expect(store.isWatched(video("a"), policy: policy))
    }

    @Test func absorbsYouTubeHistory() {
        let (store, _) = makeStore()
        var fromHistory = video("b")
        fromHistory.watchProgress = 1
        store.absorbHistory([fromHistory])
        #expect(store.isWatched(video("b"), policy: policy))
        let localOnly = WatchedPolicy(threshold: 0.9, includesMusic: false, usesYouTubeHistory: false)
        #expect(!store.isWatched(video("b"), policy: localOnly))
    }

    /// The card's red bar: the most seen anywhere — a finished video keeps a full bar, and a
    /// feed item learns its progress from the account's history.
    @Test func progressIsTheMostSeenAnywhere() {
        let (store, _) = makeStore()
        #expect(store.progress(for: video("a")) == nil)
        store.record(videoId: "a", position: 600, duration: 600)
        #expect(store.progress(for: video("a")) == 1)

        var fromHistory = video("b")
        fromHistory.watchProgress = 0.4
        store.absorbHistory([fromHistory])
        #expect(store.progress(for: video("b")) == 0.4)  // a bare feed item with the same id
        var withBar = video("b")
        withBar.watchProgress = 0.7
        #expect(store.progress(for: withBar) == 0.7)
    }

    @Test func unwatchedKeepsOrder() {
        let (store, _) = makeStore()
        store.record(videoId: "b", position: 600, duration: 600)
        #expect(store.unwatched([video("a"), video("b"), video("c")], policy: policy).map(\.id) == ["a", "c"])
    }

    @Test func survivesRelaunch() {
        let (store, place) = makeStore()
        store.record(videoId: "a", position: 600, duration: 600)
        store.updateBackfill(HistoryBackfill(token: "page7", isComplete: false))
        store.flush()
        let relaunched = place.store()
        #expect(relaunched.isWatched(video("a"), policy: policy))
        #expect(relaunched.backfill == HistoryBackfill(token: "page7", isComplete: false))
    }

    @Test func eachAccountHasItsOwn() {
        let (store, _) = makeStore()
        store.record(videoId: "a", position: 600, duration: 600)
        store.switchAccountData(from: "A", to: "B")
        #expect(!store.isWatched(video("a"), policy: policy))
        store.switchAccountData(from: "B", to: "A")
        #expect(store.isWatched(video("a"), policy: policy))
    }

    /// Data saved in UserDefaults before the file: the live account's, and a parked one's.
    @Test func movesOldDataOutOfUserDefaults() throws {
        let place = Place()
        let old = Data(#"[{"id":"a","entry":{"local":1}}]"#.utf8)
        place.defaults.set(old, forKey: "st_watched")
        place.defaults.set(Data(#"[{"id":"b","entry":{"history":1}}]"#.utf8), forKey: "st_watched#account.B")
        let store = place.store(slot: "A")
        #expect(store.isWatched(video("a"), policy: policy))
        #expect(place.defaults.data(forKey: "st_watched") == nil)
        store.switchAccountData(from: "A", to: "B")
        #expect(store.isWatched(video("b"), policy: policy))
        #expect(place.defaults.data(forKey: "st_watched#account.B") == nil)
    }

    /// The live UserDefaults data belonged to whoever was live at launch, nobody else.
    @Test func oldLiveDataStaysWithTheLiveAccount() {
        let place = Place()
        place.defaults.set(Data(#"[{"id":"a","entry":{"local":1}}]"#.utf8), forKey: "st_watched")
        let store = place.store(slot: "A")
        store.switchAccountData(from: "A", to: "C")
        #expect(!store.isWatched(video("a"), policy: policy))
    }

    @Test func forgettingAnAccountDeletesItsData() {
        let (store, place) = makeStore()
        store.record(videoId: "a", position: 600, duration: 600)
        store.switchAccountData(from: "A", to: "B")
        store.forget(accountId: "A")
        store.switchAccountData(from: "B", to: "A")
        #expect(!store.isWatched(video("a"), policy: policy))
        _ = place
    }

    /// History videos without a resume bar still count as known, so a sync can tell where the
    /// history it already has begins.
    @Test func historyWithoutProgressIsKnownButNotWatched() {
        let (store, _) = makeStore()
        #expect(store.absorbHistory([video("live")]) == 1)
        #expect(store.absorbHistory([video("live")]) == 0)
        #expect(store.progress(for: video("live")) == nil)
    }
}

// MARK: - Settings

@Suite("AppSettings — watched videos")
struct WatchedSettingsTests {
    @Test func defaults() {
        let settings = AppSettings()
        #expect(settings.hideWatchedInFeeds)
        #expect(settings.skipWatchedWhenPlayingNext)
        #expect(settings.hideWatchedThreshold == 0.9)
        #expect(!settings.watchedIncludesMusic)
        #expect(settings.watchedUsesYouTubeHistory)
    }

    @Test func feedsThatHideWatched() {
        let settings = AppSettings()
        #expect(settings.hidesWatched(in: .home))
        #expect(settings.hidesWatched(in: .subscriptions))
        #expect(settings.hidesWatched(in: .gaming))
        #expect(!settings.hidesWatched(in: .history))
        #expect(!settings.hidesWatched(in: .watchLater))
        #expect(!settings.hidesWatched(in: .music))
        var off = settings
        off.hideWatchedInFeeds = false
        #expect(!off.hidesWatched(in: .home))
    }

    @Test func roundTripsAndOldJSONDecodesToDefaults() throws {
        var original = AppSettings()
        original.hideWatchedInFeeds = false
        original.hideWatchedThreshold = 0.75
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(original))
        #expect(!decoded.hideWatchedInFeeds)
        #expect(decoded.hideWatchedThreshold == 0.75)
        let old = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"hideWatchedVideos":false}"#.utf8))
        #expect(old.hideWatchedInFeeds)
    }
}
