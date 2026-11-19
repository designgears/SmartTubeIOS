import Foundation
import Testing

@testable import SmartTubeIOSCore

/// A profile's other YouTube accounts: their feeds and channels join the main account's.
@Suite("CompanionAccounts — a profile's YouTube accounts combined")
@MainActor
struct CompanionAccountsTests {
    private func video(_ id: String, hoursAgo: Double) -> Video {
        var video = Video(id: id, title: id, channelTitle: "Channel")
        video.publishedAt = Date(timeIntervalSinceNow: -hoursAgo * 3600)
        return video
    }

    private func accounts(_ apis: [MockInnerTubeAPI]) -> CompanionAccounts {
        let accounts = CompanionAccounts()
        accounts.provider = { apis }
        return accounts
    }

    @Test func subscriptionsAreNewestFirstEachOnce() async throws {
        let main = MockInnerTubeAPI()
        main.subscriptionsResult = VideoGroup(
            title: "Subs", videos: [video("main_new", hoursAgo: 1), video("shared", hoursAgo: 5)])
        let other = MockInnerTubeAPI()
        other.subscriptionsResult = VideoGroup(
            title: "Subs", videos: [video("other_newest", hoursAgo: 0.5), video("shared", hoursAgo: 5)])
        let failing = MockInnerTubeAPI()
        failing.errorToThrow = URLError(.notConnectedToInternet)

        let group = try await accounts([other, failing]).subscriptions(main: main)
        #expect(group.videos.map(\.id) == ["other_newest", "main_new", "shared"])
    }

    @Test func channelsKeepTheMainAccountsOrder() async throws {
        let main = MockInnerTubeAPI()
        main.channelsResult = [Channel(id: "UCa", title: "A"), Channel(id: "UCshared", title: "S")]
        let other = MockInnerTubeAPI()
        other.channelsResult = [Channel(id: "UCshared", title: "S"), Channel(id: "UCb", title: "B")]
        let channels = try await accounts([other]).subscribedChannels(main: main)
        #expect(channels.map(\.id) == ["UCa", "UCshared", "UCb"])
    }

    @Test func noCompanionsIsTheMainAccountAlone() async throws {
        let main = MockInnerTubeAPI()
        main.subscriptionsResult = VideoGroup(title: "Subs", videos: [video("only", hoursAgo: 2)])
        #expect(try await accounts([]).subscriptions(main: main).videos.map(\.id) == ["only"])
    }
}
