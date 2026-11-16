import Foundation
import Testing

@testable import SmartTubeIOSCore

/// The red resume bar on history and feed items: what the watched policy and Continue
/// Watching read from the account's history.
@Suite("Watch progress — resume bar parsing")
struct WatchProgressParsingTests {
    private func lockup(overlays: [[String: Any]]) -> [String: Any] {
        [
            "contents": [
                "sectionListRenderer": [
                    "contents": [
                        [
                            "itemSectionRenderer": [
                                "contents": [
                                    [
                                        "lockupViewModel": [
                                            "rendererContext": [
                                                "commandContext": [
                                                    "onTap": [
                                                        "innertubeCommand": ["watchEndpoint": ["videoId": "watchedvid1"]]
                                                    ]
                                                ]
                                            ],
                                            "metadata": [
                                                "lockupMetadataViewModel": ["title": ["content": "Watched"]]
                                            ],
                                            "contentImage": [
                                                "thumbnailViewModel": [
                                                    "image": ["thumbnails": [["url": "https://i.ytimg.com/vi/x/hq.jpg"]]],
                                                    "overlays": overlays,
                                                ]
                                            ],
                                        ]
                                    ]
                                ]
                            ]
                        ]
                    ]
                ]
            ]
        ]
    }

    @Test func lockupReadsTheResumeBar() async throws {
        let overlays: [[String: Any]] = [
            [
                "thumbnailBottomOverlayViewModel": [
                    "progressBar": ["thumbnailOverlayProgressBarViewModel": ["startPercent": 64]],
                    "badges": [["thumbnailBadgeViewModel": ["text": "12:01"]]],
                ]
            ]
        ]
        let group = try await InnerTubeAPI().parseVideoGroupForTesting(lockup(overlays: overlays), title: nil)
        let video = try #require(group.videos.first)
        #expect(video.watchProgress == 0.64)
        #expect(video.duration == 721)
    }

    @Test func lockupWithoutResumeBarHasNoProgress() async throws {
        let group = try await InnerTubeAPI().parseVideoGroupForTesting(lockup(overlays: []), title: nil)
        #expect(try #require(group.videos.first).watchProgress == nil)
    }

    @Test func rendererOverlaysAcceptWholeAndFractionalPercents() {
        let whole: [[String: Any]] = [["thumbnailOverlayResumePlaybackRenderer": ["percentDurationWatched": 100]]]
        let fractional: [[String: Any]] = [
            ["thumbnailOverlayTimeStatusRenderer": ["text": ["simpleText": "3:12"]]],
            ["thumbnailOverlayResumePlaybackRenderer": ["percentDurationWatched": 37.5]],
        ]
        #expect(InnerTubeAPI.resumePercent(in: whole) == 100)
        #expect(InnerTubeAPI.resumePercent(in: fractional) == 37.5)
        #expect(InnerTubeAPI.resumePercent(in: [[String: Any]]()) == nil)
    }
}

@Suite("Live — player response")
struct LiveNowTests {
    @Test func liveOnlyWhileStreaming() {
        #expect(InnerTubeAPI.isLiveNow(["isLive": true, "isLiveContent": true, "lengthSeconds": "0"]))
        // An ended stream keeps isLiveContent; its replay has a length.
        #expect(!InnerTubeAPI.isLiveNow(["isLiveContent": true, "lengthSeconds": "7342"]))
        // Without isLive: a running stream has no length; an upcoming one doesn't count.
        #expect(InnerTubeAPI.isLiveNow(["isLiveContent": true, "lengthSeconds": "0"]))
        #expect(!InnerTubeAPI.isLiveNow(["isLiveContent": true, "lengthSeconds": "0", "isUpcoming": true]))
        #expect(!InnerTubeAPI.isLiveNow(["lengthSeconds": "212"]))
        #expect(!InnerTubeAPI.isLiveNow(nil))
    }
}
