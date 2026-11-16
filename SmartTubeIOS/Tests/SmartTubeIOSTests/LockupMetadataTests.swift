import Foundation
import Testing

@testable import SmartTubeIOSCore

/// Rows taken from live responses (Nov 2026) for NFL videos on each surface.
@Suite("LockupMetadata — channel, views and age by content, not position")
struct LockupMetadataTests {

    @Test func feedAndUpNextRows() {
        let meta = LockupMetadata(rows: [["NFL"], ["1M", "9h ago"]])
        #expect(meta.channelTitle == "NFL")
        #expect(meta.viewCount == 1_000_000)
        #expect(meta.age?.text == "9 hours ago")
    }

    /// Search's official card puts everything on one row.
    @Test func searchOfficialCardRow() {
        let meta = LockupMetadata(rows: [["NFL", "529K views", "6 hours ago"]])
        #expect(meta.channelTitle == "NFL")
        #expect(meta.viewCount == 529_000)
        #expect(meta.age?.text == "6 hours ago")
    }

    /// A channel's own page leaves the channel out — views must not become the channel.
    @Test func channelPageRowWithoutChannel() {
        let meta = LockupMetadata(rows: [["21K views", "6 hours ago"]])
        #expect(meta.channelTitle == nil)
        #expect(meta.viewCount == 21_000)
        #expect(meta.age?.text == "6 hours ago")
    }

    @Test func collabChannelAndLongForm() {
        let meta = LockupMetadata(rows: [["NFL and NFL Daily with Gregg Rosenthal"], ["8.9K views", "4 hours ago"]])
        #expect(meta.channelTitle == "NFL and NFL Daily with Gregg Rosenthal")
        #expect(meta.viewCount == 8_900)
    }

    @Test func liveAndNoViews() {
        let live = LockupMetadata(rows: [["KTLA 5"], ["1.2K watching"]])
        #expect(live.isLive)
        #expect(live.viewCount == 1_200)
        let none = LockupMetadata(rows: [["No views", "1 minute ago"]])
        #expect(none.channelTitle == nil)
        #expect(none.viewCount == 0)
    }

    @Test(arguments: [
        ("9h ago", "9 hours ago"), ("1d ago", "1 day ago"), ("2w ago", "2 weeks ago"), ("4mo ago", "4 months ago"),
        ("5m ago", "5 minutes ago"), ("1y ago", "1 year ago"), ("3 years ago", "3 years ago"),
        ("Streamed 2 days ago", "Streamed 2 days ago"),
    ])
    func ages(input: String, expected: String) {
        #expect(RelativeAge(input)?.text == expected)
    }

    @Test func notAnAge() {
        #expect(RelativeAge("529K views") == nil)
        #expect(RelativeAge("NFL") == nil)
    }

    @Test func ageDates() throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(try #require(RelativeAge("9h ago")).date(before: now) == now.addingTimeInterval(-9 * 3_600))
    }

    @Test(arguments: [
        ("1,585,288 views", 1_585_288), ("1.5K", 1_500), ("529K views", 529_000), ("2M", 2_000_000),
        ("1.4B views", 1_400_000_000),
    ])
    func counts(text: String, expected: Int) {
        #expect(parseCount(text) == expected)
    }
}
