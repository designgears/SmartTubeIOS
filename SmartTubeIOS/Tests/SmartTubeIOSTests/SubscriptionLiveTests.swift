import Foundation
import Testing

@testable import SmartTubeIOSCore

// MARK: - SubscriptionLiveStore

@MainActor
@Suite("SubscriptionLiveStore — subscribed channels live now")
struct SubscriptionLiveStoreTests {
    private func video(_ id: String, channel: String, channelId: String? = nil, live: Bool) -> Video {
        Video(id: id, title: id, channelTitle: channel, channelId: channelId, isLive: live)
    }

    @Test func collectsLiveStreamsAcrossFeedPages() async {
        let mock = MockInnerTubeAPI()
        mock.subscriptionsResult = VideoGroup(
            title: "Subs",
            videos: [
                video("live1", channel: "Coconut B", channelId: "@TheCoconutB", live: true),
                video("vod", channel: "The B1M", live: false),
            ],
            nextPageToken: nil)
        let store = SubscriptionLiveStore()
        await store.refresh(api: mock, token: "token")
        #expect(store.videos.map(\.id) == ["live1"])
        // Signed in before the first read, however early the screen asks.
        #expect(mock.calls.first == MockInnerTubeAPI.Call(method: "setAuthToken", args: ["token"]))
        // The feed names the channel by handle; the Channels list by UC ID and name.
        #expect(store.isLive(Channel(id: "UCcoconut", title: "Coconut B")))
        #expect(!store.isLive(Channel(id: "UCb1m", title: "The B1M")))
    }

    @Test func readsAtMostThePageLimitAndNotTooOften() async {
        let mock = MockInnerTubeAPI()
        mock.subscriptionsResult = VideoGroup(
            title: "Subs", videos: [video("live1", channel: "A", live: true)], nextPageToken: "more")
        var clock = Date(timeIntervalSince1970: 0)
        let store = SubscriptionLiveStore(now: { clock })
        await store.refresh(api: mock, token: "token")
        #expect(mock.calls.filter { $0.method == "fetchSubscriptions" }.count == SubscriptionLiveStore.pages)
        await store.refresh(api: mock, token: "token")
        #expect(mock.calls.filter { $0.method == "fetchSubscriptions" }.count == SubscriptionLiveStore.pages)
        clock += SubscriptionLiveStore.freshness + 1
        await store.refresh(api: mock, token: "token")
        #expect(mock.calls.filter { $0.method == "fetchSubscriptions" }.count == SubscriptionLiveStore.pages * 2)
    }

    @Test func aFailedReadKeepsWhatIsShown() async {
        let mock = MockInnerTubeAPI()
        mock.subscriptionsResult = VideoGroup(title: "Subs", videos: [video("live1", channel: "A", live: true)])
        var clock = Date(timeIntervalSince1970: 0)
        let store = SubscriptionLiveStore(now: { clock })
        await store.refresh(api: mock, token: "token")
        mock.errorToThrow = URLError(.notConnectedToInternet)
        clock += SubscriptionLiveStore.freshness + 1
        await store.refresh(api: mock, token: "token")
        #expect(store.videos.map(\.id) == ["live1"])
    }
}

// MARK: - ChannelSort

@Suite("ChannelSort — the Channels page order")
struct ChannelSortTests {
    private let channels = [
        Channel(id: "1", title: "beta"), Channel(id: "2", title: "Alpha"), Channel(id: "3", title: "Gamma"),
    ]

    @Test func livesFirstInEveryOrder() {
        let live: (Channel) -> Bool = { $0.id == "3" }
        #expect(ChannelSort.youTube.sorted(channels, isLive: live).map(\.id) == ["3", "1", "2"])
        #expect(ChannelSort.alphabetical.sorted(channels, isLive: live).map(\.id) == ["3", "2", "1"])
        #expect(ChannelSort.reverseAlphabetical.sorted(channels, isLive: live).map(\.id) == ["3", "1", "2"])
    }

    @Test func alphabeticalIgnoresCase() {
        #expect(ChannelSort.alphabetical.sorted(channels) { _ in false }.map(\.title) == ["Alpha", "beta", "Gamma"])
    }

    @Test func remembered() throws {
        var settings = AppSettings()
        #expect(settings.channelSort == .youTube)
        settings.channelSort = .alphabetical
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded.channelSort == .alphabetical)
    }
}
