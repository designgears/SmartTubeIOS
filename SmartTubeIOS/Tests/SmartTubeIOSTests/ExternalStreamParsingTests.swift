import Foundation
import Testing

@testable import SmartTubeIOSCore

// Shapes trimmed from real Twitch GQL and Kick website answers (2026-11-19); names made up.

private func json(_ text: String) -> Data { Data(text.utf8) }

// MARK: - Ids

@Suite("ExternalID — Twitch and Kick ids next to YouTube's")
struct ExternalIDTests {
    @Test func roundTrips() {
        #expect(ExternalID.parse(ExternalID.live(.twitch, "SomeStreamer"))
            == ExternalID.Parsed(platform: .twitch, kind: .live, key: "somestreamer"))
        #expect(ExternalID.parse(ExternalID.vod(.kick, "716d63b6-afa9")) == ExternalID.Parsed(platform: .kick, kind: .vod, key: "716d63b6-afa9"))
        #expect(ExternalID.parse(ExternalID.channel(.kick, "some-slug")) == ExternalID.Parsed(platform: .kick, kind: .channel, key: "some-slug"))
    }

    @Test func youTubeIdsStayYouTube() {
        for id in ["dQw4w9WgXcQ", "UCSJ4gkVC6NrvII8umztf0Ow", "@handle", "youtube:live:x", "twitch:", "twitch:what:x"] {
            #expect(ExternalID.parse(id) == nil || id.hasPrefix("youtube"))
            #expect(StreamPlatform(id: id) == .youtube)
        }
        #expect(Video(id: "twitch:vod:1", title: "", channelTitle: "").isExternal)
        #expect(!Video(id: "dQw4w9WgXcQ", title: "", channelTitle: "").isExternal)
    }
}

// MARK: - Twitch

@Suite("TwitchClient — parsing GQL answers")
struct TwitchParsingTests {
    @Test func liveAndOfflineUsers() throws {
        let data = json(
            """
            {"data":{"users":[
              {"id":"1","login":"livestreamer","displayName":"LiveStreamer","profileImageURL":"https://cdn/p.png",
               "description":"hi","followers":{"totalCount":1234567},
               "stream":{"id":"9","title":"Playing things","viewersCount":5300,"createdAt":"2026-11-19T15:00:00Z",
                         "game":{"displayName":"Just Chatting"},"previewImageURL":"https://cdn/live-640x360.jpg"}},
              {"id":"2","login":"offline","displayName":"Offline","profileImageURL":null,"description":"",
               "followers":{"totalCount":12},"stream":null},
              null
            ]}}
            """)
        let channels = TwitchClient.parseUsers(data)
        #expect(channels.map(\.id) == ["twitch:livestreamer", "twitch:offline"])
        let live = try #require(channels[0].live)
        #expect(live.id == "twitch:live:livestreamer")
        #expect(live.isLive && live.viewCount == 5300 && live.title == "Playing things")
        #expect(live.channelId == "twitch:livestreamer" && live.badges == ["Just Chatting"])
        #expect(channels[0].channel.subscriberCount == "1.2M followers")
        #expect(channels[1].live == nil && channels[1].channel.description == nil)
    }

    @Test func pastBroadcastsWithCursor() {
        let data = json(
            """
            {"data":{"user":{"login":"s","displayName":"S","videos":{"edges":[
              {"cursor":"c1","node":{"id":"2931745878","title":"long sesh","lengthSeconds":10930,
               "createdAt":"2026-11-17T21:46:29Z","viewCount":102160,"previewThumbnailURL":"https://cdn/t.jpg",
               "owner":{"login":"s","displayName":"S"}}}],"pageInfo":{"hasNextPage":true}}}}}
            """)
        let page = TwitchClient.parseVideos(data)
        #expect(page.videos.map(\.id) == ["twitch:vod:2931745878"])
        #expect(page.videos.first?.duration == 10930 && page.videos.first?.channelId == "twitch:s")
        #expect(page.cursor == "c1")
    }

    @Test func playbackTokenAndUsherURL() throws {
        let data = json(#"{"data":{"streamPlaybackAccessToken":{"value":"{\"a\":1}","signature":"abc"}}}"#)
        let token = try #require(TwitchClient.parsePlaybackToken(data, vod: false))
        let live = TwitchClient.usherURL(for: .init(platform: .twitch, kind: .live, key: "Some"), token: token)
        #expect(live.host == "usher.ttvnw.net" && live.path == "/api/channel/hls/some.m3u8")
        let query = URLComponents(url: live, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(query.first { $0.name == "token" }?.value == #"{"a":1}"#)
        #expect(query.first { $0.name == "sig" }?.value == "abc")
        let vod = TwitchClient.usherURL(for: .init(platform: .twitch, kind: .vod, key: "123"), token: token)
        #expect(vod.path == "/vod/123.m3u8")
        #expect(TwitchClient.parsePlaybackToken(json(#"{"errors":[{}]}"#), vod: true) == nil)
    }

    @Test func searchSkipsNonUsers() {
        let data = json(
            #"{"data":{"searchFor":{"channels":{"edges":[{"item":{"login":"a","displayName":"A","stream":null}},{"item":{}}]}}}}"#)
        #expect(TwitchClient.parseSearch(data).map(\.id) == ["twitch:a"])
    }

    @Test func queryStringsAreEscaped() {
        #expect(TwitchClient.quoted(#"say "hi"\"#) == #""say \"hi\"\\""#)
    }
}

// MARK: - Kick

@Suite("KickClient — parsing Kick's website API")
struct KickParsingTests {
    @Test func liveChannel() throws {
        let data = json(
            """
            {"slug":"some-one","followers_count":1973046,"chatroom":{"id":668},
             "banner_image":{"url":"https://files/banner"},
             "playback_url":"https://x.playback.live-video.net/api/video/v1/a.m3u8",
             "user":{"username":"SomeOne","profile_pic":"https://files/pic.webp","bio":""},
             "livestream":{"is_live":true,"session_title":"GTA","viewer_count":75174,"start_time":"2026-11-19 16:30:50",
                           "thumbnail":null,"categories":[{"name":"Grand Theft Auto VI"}]}}
            """)
        let channel = try #require(KickClient.parseChannel(data))
        #expect(channel.id == "kick:some-one" && channel.chatroomID == 668)
        #expect(channel.channel.title == "SomeOne" && channel.channel.subscriberCount == "1.9M followers")
        let live = try #require(channel.live)
        #expect(live.id == "kick:live:some-one" && live.viewCount == 75174 && live.badges == ["Grand Theft Auto VI"])
        #expect(live.thumbnailURL?.absoluteString == "https://files/banner")  // no live thumbnail here
        #expect(live.publishedAt == Date(timeIntervalSince1970: 1_795_105_850))
        #expect(KickClient.parsePlaybackURL(data, vod: false)?.host == "x.playback.live-video.net")
    }

    @Test func offlineChannelHasNoStream() throws {
        let data = json(#"{"slug":"quiet","user":{"username":"Quiet"},"livestream":null,"playback_url":"https://x/a.m3u8"}"#)
        #expect(try #require(KickClient.parseChannel(data)).live == nil)
        #expect(KickClient.parsePlaybackURL(data, vod: false) == nil)
    }

    @Test func livestreamAnswer() {
        let live = json(
            #"{"data":{"session_title":"T","viewers":12,"created_at":"2026-11-19T16:30:53.000000Z","thumbnail":{"src":"https://img/720.webp"},"category":{"name":"Chess"}}}"#
        )
        let video = KickClient.parseLivestream(live, slug: "s")
        #expect(video?.thumbnailURL?.absoluteString == "https://img/720.webp" && video?.badges == ["Chess"])
        #expect(video?.publishedAt == Date(timeIntervalSince1970: 1_795_105_853))
        #expect(KickClient.parseLivestream(json(#"{"data":null}"#), slug: "s") == nil)
    }

    @Test func pastBroadcastsInSeconds() {
        let data = json(
            """
            [{"is_live":false,"session_title":"Old","duration":83735000,"start_time":"2026-11-18 06:27:54","views":147703,
              "thumbnail":{"src":"https://img/vod.webp"},"video":{"uuid":"716d63b6"}},
             {"is_live":true,"session_title":"Now","video":{"uuid":"live1"}}]
            """)
        let videos = KickClient.parseVideos(data, slug: "s")
        #expect(videos.map(\.id) == ["kick:vod:716d63b6"])
        #expect(videos.first?.duration == 83735 && videos.first?.viewCount == 147703)
        #expect(KickClient.parsePlaybackURL(json(#"{"source":"https://stream.kick.com/v.m3u8"}"#), vod: true)?.path == "/v.m3u8")
    }

    @Test func searchMarksLiveChannels() {
        let data = json(
            #"{"channels":[{"slug":"a","isLive":true,"user":{"username":"A","profile_pic":null}},{"slug":"b","isLive":false,"user":{"username":"B"}}]}"#
        )
        let found = KickClient.parseSearch(data)
        #expect(found.map(\.id) == ["kick:a", "kick:b"])
        #expect(found[0].live?.isLive == true && found[1].live == nil)
    }
}
