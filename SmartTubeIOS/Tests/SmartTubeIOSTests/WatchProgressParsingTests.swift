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

@Suite("Live — HLS variants")
struct LiveVariantTests {
    /// Trimmed from a real YouTube live multivariant playlist (Lofi Girl).
    private let live = """
        #EXTM3U
        #EXT-X-INDEPENDENT-SEGMENTS
        #EXT-X-STREAM-INF:BANDWIDTH=269034,CODECS="mp4a.40.5,avc1.42C00B",RESOLUTION=256x144,FRAME-RATE=15
        https://manifest.googlevideo.com/api/manifest/hls_playlist/id/x.1/itag/91/source/yt_live_broadcast/live/1/a
        #EXT-X-STREAM-INF:BANDWIDTH=410000,CODECS="mp4a.40.5,avc1.4D4015",RESOLUTION=426x240,FRAME-RATE=30
        https://manifest.googlevideo.com/api/manifest/hls_playlist/id/x.1/itag/92/source/yt_live_broadcast/live/1/b
        #EXT-X-STREAM-INF:BANDWIDTH=1000000,CODECS="mp4a.40.2,avc1.4D401E",RESOLUTION=640x360,FRAME-RATE=30
        https://manifest.googlevideo.com/api/manifest/hls_playlist/id/x.1/itag/93/source/yt_live_broadcast/live/1/c
        #EXT-X-STREAM-INF:BANDWIDTH=5000000,CODECS="mp4a.40.2,avc1.640028",RESOLUTION=1920x1080,FRAME-RATE=30
        https://manifest.googlevideo.com/api/manifest/hls_playlist/id/x.1/itag/96/source/yt_live_broadcast/live/1/d
        """

    @Test func liveKeepsTheVariantsMatchingTheBest() {
        let result = consistentLiveVariants(live)
        #expect(hlsMultivariantPlaylistURIs(result).map { String($0.suffix(1)) } == ["c", "d"])
        #expect(!result.contains("RESOLUTION=256x144"))
        #expect(!result.contains("RESOLUTION=426x240"))
    }

    @Test func videosAreUntouched() {
        let video = live.replacingOccurrences(of: "source/yt_live_broadcast/live/1/", with: "source/youtube/")
        #expect(consistentLiveVariants(video) == video)
    }
}
