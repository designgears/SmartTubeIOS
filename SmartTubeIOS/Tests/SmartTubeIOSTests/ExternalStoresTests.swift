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

    /// Each profile has its own follows: switching parks one profile's and brings the other's.
    @Test func followsBelongToTheProfile() {
        let suite = defaults()
        let store = ExternalFollowStore(defaults: suite)
        store.follow(Channel(id: "kick:jo", title: "Jo's"))
        store.switchAccountData(from: "jo", to: "sam")
        #expect(store.all.isEmpty)
        store.follow(Channel(id: "twitch:sam", title: "Sam's"))
        store.switchAccountData(from: "sam", to: "jo")
        #expect(store.all.map(\.id) == ["kick:jo"])
        #expect(ExternalFollowStore(defaults: suite).all.map(\.id) == ["kick:jo"])  // across launches
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

// MARK: - ExternalFeedStore

@MainActor
@Suite("ExternalFeedStore — followed Twitch and Kick broadcasts in Subscriptions")
struct ExternalFeedStoreTests {
    nonisolated private static func vod(_ id: String, channel: String, hoursAgo: Double, live: Bool = false) -> Video {
        Video(
            id: id, title: id, channelTitle: "raw", channelId: channel,
            publishedAt: Date(timeIntervalSinceNow: -hoursAgo * 3600), isLive: live)
    }

    @Test func latestBroadcastsNewestFirstAFewPerChannel() async {
        let store = ExternalFeedStore(
            sources: .init(
                twitch: { _ in
                    (0..<10).map { Self.vod("twitch:vod:\($0)", channel: "twitch:t", hoursAgo: Double($0) * 10) }
                },
                kick: { _ in
                    [
                        Self.vod("kick:live:k", channel: "kick:k", hoursAgo: 0, live: true),  // Live Now's
                        Self.vod("kick:vod:a", channel: "kick:k", hoursAgo: 15),
                    ]
                }))
        await store.refresh(channels: [Channel(id: "twitch:t", title: "Tee"), Channel(id: "kick:k", title: "Kay")])
        #expect(store.videos.count == ExternalFeedStore.perChannel + 1)
        #expect(store.videos.prefix(3).map(\.id) == ["twitch:vod:0", "twitch:vod:1", "kick:vod:a"])
        #expect(store.videos.first?.channelTitle == "Tee")
        store.reset()
        #expect(store.videos.isEmpty)
    }

    /// Broadcasts older than the loaded part of the YouTube feed wait for more of it to load.
    @Test func blendedIntoAPagedFeed() {
        let feed = [Self.vod("yt1", channel: "UC1", hoursAgo: 1), Self.vod("yt2", channel: "UC2", hoursAgo: 20)]
        let external = [
            Self.vod("twitch:vod:new", channel: "twitch:t", hoursAgo: 5),
            Self.vod("old", channel: "kick:k", hoursAgo: 90),
        ]
        #expect(
            ExternalFeedStore.blended(feed, with: external, feedIsComplete: false).map(\.id)
                == ["yt1", "twitch:vod:new", "yt2"])
        #expect(ExternalFeedStore.blended(feed, with: external, feedIsComplete: true).last?.id == "old")
        #expect(ExternalFeedStore.blended([], with: external, feedIsComplete: false).count == 2)
    }
}
