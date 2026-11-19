import Foundation
import Testing

@testable import SmartTubeIOSCore

// MARK: - ExternalFollowStore

@MainActor
@Suite("ExternalFollowStore — Twitch and Kick follows on the device")
struct ExternalFollowStoreTests {
    // swiftlint:disable:next force_unwrapping
    private func defaults() -> UserDefaults { UserDefaults(suiteName: "follows-\(UUID().uuidString)")! }

    @Test func followsPerPlatformNewestFirstAndSurvivesRelaunch() {
        let suite = defaults()
        let store = ExternalFollowStore(defaults: suite)
        store.follow(Channel(id: "kick:a", title: "A"))
        store.follow(Channel(id: "twitch:b", title: "B"))
        store.follow(Channel(id: "kick:c", title: "C"))
        store.follow(Channel(id: "UCyoutube", title: "YouTube channel"))  // not for this store
        #expect(store.channels(.kick).map(\.id) == ["kick:c", "kick:a"])
        #expect(store.channels(.twitch).map(\.id) == ["twitch:b"])
        #expect(!store.isFollowing("UCyoutube"))
        store.unfollow("kick:a")
        let relaunched = ExternalFollowStore(defaults: suite)
        #expect(relaunched.all.map(\.id) == ["kick:c", "twitch:b"])
    }

    @Test func updateRefreshesNameAndAvatar() {
        let store = ExternalFollowStore(defaults: defaults())
        store.follow(Channel(id: "kick:a", title: "old"))
        store.update(Channel(id: "kick:a", title: "New Name"))
        store.update(Channel(id: "kick:unfollowed", title: "ignored"))
        #expect(store.all.map(\.title) == ["New Name"])
    }
}

// MARK: - ExternalLiveStore

private func liveVideo(_ id: String, channel: String, viewers: Int) -> Video {
    Video(id: id, title: id, channelTitle: "", channelId: channel, viewCount: viewers, isLive: true)
}

@MainActor
@Suite("ExternalLiveStore — followed Twitch and Kick channels live now")
struct ExternalLiveStoreTests {
    /// Kick lookups run concurrently, so the record is locked.
    private final class Calls: @unchecked Sendable {
        private let lock = NSLock()
        private var twitchCalls: [[String]] = []
        private var kickCalls: [String] = []
        var twitch: [[String]] { lock.withLock { twitchCalls } }
        var kick: [String] { lock.withLock { kickCalls } }
        func record(twitch logins: [String]) { lock.withLock { twitchCalls.append(logins) } }
        func record(kick slug: String) { lock.withLock { kickCalls.append(slug) } }
    }

    @Test func mergesBothPlatformsMostWatchedFirst() async {
        let calls = Calls()
        let store = ExternalLiveStore(
            sources: .init(
                twitch: { logins in
                    calls.record(twitch: logins)
                    return [liveVideo("twitch:live:t1", channel: "twitch:t1", viewers: 50)]
                },
                kick: { slug in
                    calls.record(kick: slug)
                    return slug == "k1" ? liveVideo("kick:live:k1", channel: "kick:k1", viewers: 900) : nil
                }))
        await store.refresh(channels: [
            Channel(id: "twitch:t1", title: "T One"), Channel(id: "kick:k1", title: "K One"),
            Channel(id: "kick:k2", title: "K Two"),
        ])
        #expect(store.videos.map(\.id) == ["kick:live:k1", "twitch:live:t1"])
        #expect(store.videos.first?.channelTitle == "K One")  // the followed channel's name
        #expect(store.liveVideo(of: "twitch:t1")?.id == "twitch:live:t1")
        #expect(store.videos(.twitch).count == 1)
        #expect(calls.twitch == [["t1"]] && Set(calls.kick) == ["k1", "k2"])
    }

    @Test func readsAgainOnlyWhenStaleOrFollowsChange() async {
        let calls = Calls()
        var clock = Date(timeIntervalSince1970: 0)
        let store = ExternalLiveStore(
            sources: .init(
                twitch: {
                    calls.record(twitch: $0)
                    return []
                }, kick: { _ in nil }), now: { clock })
        let follows = [Channel(id: "twitch:a", title: "A")]
        await store.refresh(channels: follows)
        await store.refresh(channels: follows)
        #expect(calls.twitch.count == 1)
        await store.refresh(channels: follows + [Channel(id: "twitch:b", title: "B")])
        #expect(calls.twitch.count == 2)
        clock += ExternalLiveStore.freshness + 1
        await store.refresh(channels: follows + [Channel(id: "twitch:b", title: "B")])
        #expect(calls.twitch.count == 3)
    }
}
