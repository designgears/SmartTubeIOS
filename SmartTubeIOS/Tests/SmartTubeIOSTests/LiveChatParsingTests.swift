import Foundation
import Testing

@testable import SmartTubeIOSCore

// Shapes from real Twitch IRC and Kick Centrifugo frames (2026-11-19); names made up.

@Suite("Live chat — Twitch IRC and Kick Centrifugo messages")
struct LiveChatParsingTests {
    @Test func twitchMessageWithTags() throws {
        let line =
            "@badge-info=;badges=;color=#FF69B4;display-name=SomeViewer;emotes=;id=15f44c17-79e4;mod=0 "
            + ":someviewer!someviewer@someviewer.tmi.twitch.tv PRIVMSG #streamer :hello there: friends"
        let message = try #require(LiveChatParsing.twitch(line))
        #expect(message.author == "SomeViewer" && message.color == "#FF69B4")
        #expect(message.text == "hello there: friends" && message.id == "15f44c17-79e4")
    }

    @Test func twitchWithoutColorOrNameAndActions() throws {
        let line = "@color=;display-name=;id=1 :plain!plain@plain.tmi.twitch.tv PRIVMSG #s :\u{1}ACTION waves\u{1}"
        let message = try #require(LiveChatParsing.twitch(line))
        #expect(message.author == "plain" && message.color == nil && message.text == "waves")
        #expect(LiveChatParsing.twitch(":tmi.twitch.tv 001 justinfan123 :Welcome, GLHF!") == nil)
        #expect(LiveChatParsing.twitch("PING :tmi.twitch.tv") == nil)
    }

    @Test func kickChatFrame() throws {
        let inner =
            ##"{"id":"d4f4","content":"so good [emote:5748001:KEKW] lol","sender":{"username":"Viewer","identity":{"color":"#FF2C56"}}}"##
        let frame = LiveChatParsing.json([
            "push": [
                "channel": "chatrooms.1.v2",
                "pub": ["data": ["event": "App\\Events\\ChatMessageEvent", "data": inner]],
            ]
        ])
        let message = try #require(LiveChatParsing.kick(frame))
        #expect(message.author == "Viewer" && message.color == "#FF2C56" && message.id == "d4f4")
        #expect(message.text == "so good KEKW lol")
    }

    @Test func kickIgnoresOtherFrames() {
        #expect(LiveChatParsing.kick(#"{"id":2,"subscribe":{}}"#) == nil)
        let banned = LiveChatParsing.json([
            "push": ["pub": ["data": ["event": "App\\Events\\UserBannedEvent", "data": "{}"]]]
        ])
        #expect(LiveChatParsing.kick(banned) == nil)
    }

    @Test func kickConnectionAnswers() {
        let server = Data(
            #"{"data":{"connections":[{"credentials":{"url":"wss://realtime.example/connection/websocket"},"provider":"centrifugo"}],"mode":"websocket"}}"#
                .utf8)
        #expect(LiveChatParsing.kickServer(server)?.host == "realtime.example")
        #expect(LiveChatParsing.kickToken(Data(#"{"data":{"token":"abc"}}"#.utf8)) == "abc")
        #expect(LiveChatParsing.kickServer(Data(#"{"data":{"connections":[{"provider":"pusher"}]}}"#.utf8)) == nil)
    }

    @MainActor
    @Test func feedKeepsTheNewestMessages() {
        let feed = LiveChatFeed()
        for index in 0..<(LiveChatFeed.capacity + 5) {
            feed.append(ChatMessage(id: "\(index)", author: "a", color: nil, text: "\(index)"))
        }
        #expect(feed.messages.count == LiveChatFeed.capacity)
        #expect(feed.messages.first?.id == "5" && feed.messages.last?.id == "\(LiveChatFeed.capacity + 4)")
        #expect(LiveChatFeed.isAvailable(for: Video(id: "kick:live:x", title: "", channelTitle: "")))
        #expect(!LiveChatFeed.isAvailable(for: Video(id: "twitch:vod:1", title: "", channelTitle: "")))
    }
}
