import Foundation
import Testing

@testable import SmartTubeIOSCore

// Playlist and emote shapes from Twitch, Kick, 7TV, BetterTTV and FFZ answers (2026-11-19).

// MARK: - Twitch ads

@Suite("TwitchAds — spotting Twitch's stitched ads")
struct TwitchAdsTests {
    private let live = """
        #EXTM3U
        #EXT-X-TARGETDURATION:6
        #EXT-X-MEDIA-SEQUENCE:9393
        #EXT-X-DATERANGE:ID="playlist-session-1",CLASS="twitch-session",START-DATE="2026-11-19T17:10:54Z"
        #EXT-X-DATERANGE:ID="trigger-1",CLASS="twitch-trigger",START-DATE="2026-11-19T17:10:23Z"
        #EXTINF:2.000,live
        https://video-edge.example/v1/segment/a.ts
        #EXTINF:2.000,live
        https://video-edge.example/v1/segment/b.ts
        """

    @Test func aLivePlaylistHasNoAds() {
        #expect(!TwitchAds.hasAds(live))
    }

    @Test func stitchedAdsAreSpotted() {
        let preroll = """
            #EXTM3U
            #EXT-X-DATERANGE:ID="stitched-ad-1795110000-30",CLASS="twitch-stitched-ad",START-DATE="2026-11-19T17:00:00Z"
            #EXTINF:2.000,Amazon|2474283100495.0
            https://video-edge.example/v1/segment/ad.ts
            """
        #expect(TwitchAds.hasAds(preroll))
        // A segment that isn't titled `live`, or an ad segment path, is enough on its own.
        #expect(TwitchAds.hasAds("#EXTINF:2.000,Amazon|1\nhttps://x/seg.ts"))
        #expect(TwitchAds.hasAds("#EXTINF:2.000,live\nhttps://x/adsquared/seg.ts"))
    }

    @Test func theSmallestVideoVariantIsWatched() {
        let multivariant = """
            #EXTM3U
            #EXT-X-STREAM-INF:BANDWIDTH=8000000,RESOLUTION=1920x1080,VIDEO="1080p60"
            https://weaver.example/1080.m3u8
            #EXT-X-STREAM-INF:BANDWIDTH=230000,RESOLUTION=284x160,VIDEO="160p30"
            https://weaver.example/160.m3u8
            #EXT-X-STREAM-INF:BANDWIDTH=160000,CODECS="mp4a.40.2",VIDEO="audio_only"
            https://weaver.example/audio.m3u8
            """
        #expect(TwitchAds.watchedVariant(in: multivariant)?.lastPathComponent == "160.m3u8")
        #expect(TwitchAds.watchedVariant(in: "#EXTM3U") == nil)
    }
}

// MARK: - Emotes

@Suite("Chat emotes — Twitch, Kick and community emotes as pictures")
struct ChatEmotesTests {
    @Test func twitchEmotesByPosition() {
        // "Kappa hi 😀 Kappa": positions count code points, so the emoji counts once.
        let parts = NativeEmotes.twitchParts("Kappa hi 😀 Kappa", emotesTag: "25:0-4,11-15")
        #expect(parts.map(\.plain) == ["Kappa", " hi 😀 ", "Kappa"])
        guard case .emote(let name, let url) = parts[0] else {
            Issue.record("not an emote")
            return
        }
        #expect(name == "Kappa" && url.absoluteString.contains("/emoticons/v2/25/static/dark/"))
        #expect(NativeEmotes.twitchParts("plain", emotesTag: "") == [.text("plain")])
        #expect(NativeEmotes.twitchParts("short", emotesTag: "1:3-40") == [.text("short")])  // out of range
    }

    @Test func kickEmoteCodes() {
        let parts = NativeEmotes.kickParts("so good [emote:5748001:KEKW] lol")
        #expect(parts.map(\.plain) == ["so good ", "KEKW", " lol"])
        if case .emote(_, let url) = parts[1] { #expect(url.absoluteString.hasSuffix("/emotes/5748001/fullsize")) }
    }

    @Test func communityEmotesReplaceWholeWords() throws {
        let catalog = EmoteCatalog(emotes: ["HUSS": try #require(URL(string: "https://cdn/huss"))])
        let parts = catalog.apply([
            .text("HUSS HUSS no HUSSY"), .emote(name: "Kappa", url: try #require(URL(string: "https://k"))),
        ])
        #expect(parts.map(\.plain) == ["HUSS", " ", "HUSS", " no HUSSY", "Kappa"])
    }

    @Test func sevenTVPrefersTheStillPicture() {
        let json: [String: Any] = [
            "emote_set": [
                "emotes": [
                    [
                        "name": "Thinking",
                        "data": [
                            "host": [
                                "url": "//cdn.7tv.app/emote/01EZT9",
                                "files": [
                                    ["name": "1x.webp"], ["name": "2x.webp", "static_name": "2x_static.webp"],
                                ],
                            ]
                        ],
                    ]
                ]
            ]
        ]
        #expect(
            EmoteCatalog.parseSevenTV(json)["Thinking"]?.absoluteString
                == "https://cdn.7tv.app/emote/01EZT9/2x_static.webp")
    }

    @Test func betterTTVAndFFZ() {
        let bttv: [String: Any] = ["channelEmotes": [["id": "55c4", "code": "xD"]], "sharedEmotes": []]
        #expect(EmoteCatalog.parseBTTV(bttv)["xD"]?.absoluteString == "https://cdn.betterttv.net/emote/55c4/2x")
        #expect(EmoteCatalog.parseBTTV([["id": "g1", "code": "LUL"]])["LUL"] != nil)
        let ffz: [String: Any] = [
            "sets": [
                "3": [
                    "emoticons": [
                        [
                            "name": "ZrehplaR",
                            "urls": [
                                "1": "https://cdn.frankerfacez.com/emote/9/1",
                                "2": "https://cdn.frankerfacez.com/emote/9/2",
                            ],
                        ]
                    ]
                ]
            ]
        ]
        #expect(EmoteCatalog.parseFFZ(ffz)["ZrehplaR"]?.lastPathComponent == "2")
    }
}

// MARK: - Settings

@Suite("StreamingSettings — Settings › Twitch & Kick")
struct StreamingSettingsTests {
    @Test func onByDefaultAlsoForOldSettings() throws {
        let old = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(old.streaming == StreamingSettings())
        #expect(old.streaming.blockTwitchAds && old.streaming.chatEmotes && old.streaming.thirdPartyEmotes)
        let partial = try JSONDecoder().decode(
            AppSettings.self, from: Data(#"{"streaming":{"chatEmotes":false}}"#.utf8))
        #expect(!partial.streaming.chatEmotes && partial.streaming.blockTwitchAds)
    }

    @Test func roundTrips() throws {
        var settings = AppSettings()
        settings.streaming.blockTwitchAds = false
        settings.streaming.thirdPartyEmotes = false
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded.streaming == settings.streaming)
    }
}
