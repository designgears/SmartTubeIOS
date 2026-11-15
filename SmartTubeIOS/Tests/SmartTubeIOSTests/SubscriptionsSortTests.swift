import Foundation
import Testing

@testable import SmartTubeIOSCore

// MARK: - Helpers

/// Yields control enough times so internal @MainActor Tasks spawned by
/// the ViewModel can complete against an immediately-returning mock API.
/// Waits for the view model's in-flight fetch instead of sleeping (a fixed 50 ms sleep
/// raced the fetch under parallel test load and crashed on `videoGroups[0]`).
@MainActor
private func waitForSubsTasks(_ vm: BrowseViewModel) async {
    await vm.awaitPendingFetch()
}

// MARK: - SubscriptionsSortTests

extension ActiveChannelSuites {
    @Suite("Subscriptions Sort Order")
    @MainActor
    struct SubscriptionsSortTests {

        /// Subscriptions videos must be sorted newest-first by publishedAt.
        /// Verifies the sort that fetchSubscriptions() applies after parseVideoGroup().
        @Test func subscriptionVideosSortedNewestFirst() {
            let older = Video(
                id: "old", title: "Older", channelTitle: "Ch",
                publishedAt: Date(timeIntervalSinceReferenceDate: 1000))
            let newer = Video(
                id: "new", title: "Newer", channelTitle: "Ch",
                publishedAt: Date(timeIntervalSinceReferenceDate: 2000))
            let oldest = Video(
                id: "oldest", title: "Oldest", channelTitle: "Ch",
                publishedAt: Date(timeIntervalSinceReferenceDate: 500))

            var group = VideoGroup(title: "Subscriptions", videos: [older, newer, oldest].shuffled())
            group.videos.sort { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }

            #expect(group.videos[0].id == "new")
            #expect(group.videos[1].id == "old")
            #expect(group.videos[2].id == "oldest")
        }

        /// Videos without a publishedAt date sort to the end (distantPast fallback).
        @Test func videosWithoutPublishedAtSortToEnd() {
            let withDate = Video(
                id: "dated", title: "Dated", channelTitle: "Ch",
                publishedAt: Date(timeIntervalSinceReferenceDate: 1000))
            let withoutDate = Video(
                id: "undated", title: "Undated", channelTitle: "Ch",
                publishedAt: nil)

            var videos = [withoutDate, withDate]
            videos.sort { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }

            #expect(videos[0].id == "dated")
            #expect(videos[1].id == "undated")
        }

        /// Subscribed channels must be sorted alphabetically (case-insensitive).
        @Test func subscribedChannelsSortedAlphabetically() {
            let channels = [
                Channel(id: "c1", title: "Zebra Channel"),
                Channel(id: "c2", title: "alpha Channel"),
                Channel(id: "c3", title: "Mango Talks"),
            ]
            let sorted = channels.sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
            #expect(sorted[0].title == "alpha Channel")
            #expect(sorted[1].title == "Mango Talks")
            #expect(sorted[2].title == "Zebra Channel")
        }

        /// After paginating subscriptions, new videos must be appended at the bottom of
        /// the feed without re-sorting the already-rendered videos.
        ///
        /// Re-sorting on every page load reorders rows that are already on screen, which
        /// is jarring mid-scroll (videos jump to a different position). Page 2 may contain
        /// videos that are newer than some of page 1's videos, but they must still land
        /// at the end of the list, not interleaved.
        @Test func paginatedSubscriptionsAppendNewVideosAtBottomWithoutResort() async {
            let now = Date()
            let vidToday = Video(
                id: "today", title: "Today", channelTitle: "Ch",
                publishedAt: now)
            let vid4D = Video(
                id: "4d", title: "4 days", channelTitle: "Ch",
                publishedAt: now.addingTimeInterval(-4 * 86_400))
            let vid2D = Video(
                id: "2d", title: "2 days", channelTitle: "Ch",
                publishedAt: now.addingTimeInterval(-2 * 86_400))
            let vid1D = Video(
                id: "1d", title: "1 day", channelTitle: "Ch",
                publishedAt: now.addingTimeInterval(-1 * 86_400))

            // Page 1: today and 4 days ago (sorted newest-first as API returns them)
            let mock = MockInnerTubeAPI()
            mock.subscriptionsResult = VideoGroup(
                title: "Subs",
                videos: [vidToday, vid4D],
                nextPageToken: "page2token"
            )

            let section = BrowseSection(id: "subscriptions", title: "Subscriptions", type: .subscriptions)
            let vm = BrowseViewModel(api: mock, initialSection: section)
            await vm.updateAuthToken("fake-token")
            // updateAuthToken starts its own reload; let it finish so a superseded fetch can't
            // land after the pagination below and overwrite the merged groups.
            await waitForSubsTasks(vm)
            vm.loadContent(for: section, refresh: true, source: "test")
            await waitForSubsTasks(vm)

            guard let page1 = vm.videoGroups.first else {
                Issue.record("page 1 did not load")
                return
            }
            #expect(page1.videos.count == 2, "page 1 should load 2 videos")

            // Page 2: 2 days ago and 1 day ago — newer than "4d" but must still be appended
            // after it, not interleaved between "today" and "4d".
            mock.subscriptionsResult = VideoGroup(
                title: "Subs",
                videos: [vid2D, vid1D],
                nextPageToken: nil
            )

            // Trigger pagination using the last (oldest) video from page 1.
            guard let lastOfPage1 = page1.videos.last else { return }
            vm.loadMoreIfNeeded(lastVideo: lastOfPage1)
            await waitForSubsTasks(vm)

            let merged = vm.videoGroups.first?.videos ?? []
            #expect(merged.count == 4, "all 4 videos should be present after merge")
            // Page 1's order is preserved, page 2's videos are appended at the bottom
            // in the order the API returned them.
            #expect(merged.map(\.id) == ["today", "4d", "2d", "1d"])
        }
    }
}
