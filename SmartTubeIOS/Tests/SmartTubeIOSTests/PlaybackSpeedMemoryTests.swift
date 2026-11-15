import Foundation
import Testing

@testable import SmartTubeIOSCore

@Suite("Playback speed memory")
struct PlaybackSpeedMemoryTests {
    @Test func musicVideoTypeMarksMusic() {
        #expect(
            PlayerInfo.looksLikeMusic(musicVideoType: "MUSIC_VIDEO_TYPE_OMV", category: nil, channelTitle: "Anyone"))
    }

    @Test func musicCategoryMarksMusic() {
        #expect(PlayerInfo.looksLikeMusic(musicVideoType: nil, category: "Music", channelTitle: "Anyone"))
    }

    @Test func topicAndVevoChannelsAreMusic() {
        #expect(PlayerInfo.looksLikeMusic(musicVideoType: nil, category: nil, channelTitle: "Daft Punk - Topic"))
        #expect(PlayerInfo.looksLikeMusic(musicVideoType: nil, category: nil, channelTitle: "TheWeekndVEVO"))
    }

    @Test func musicTitleTagsMarkMusic() {
        #expect(
            PlayerInfo.looksLikeMusic(
                musicVideoType: nil, category: nil, channelTitle: "Solitude Songs",
                title: "The Weeknd, Playboi Carti & Madonna - Popular (Lyrics)"))
        #expect(
            PlayerInfo.looksLikeMusic(
                musicVideoType: nil, category: nil, channelTitle: "Some Artist",
                title: "Song Name [Official Music Video]"))
        #expect(
            !PlayerInfo.looksLikeMusic(
                musicVideoType: nil, category: nil, channelTitle: "Gamers Nexus",
                title: "Audio interface review: the best budget picks"))
    }

    @Test func regularVideosAreNotMusic() {
        #expect(!PlayerInfo.looksLikeMusic(musicVideoType: nil, category: "Education", channelTitle: "Veritasium"))
        #expect(!PlayerInfo.looksLikeMusic(musicVideoType: "", category: nil, channelTitle: "Vevo Fan Reviews"))
    }

    @Test func channelSpeedsDecodeAndDefaultToEmpty() throws {
        let decoded = try JSONDecoder().decode(
            AppSettings.self, from: Data(#"{"channelPlaybackSpeeds":{"UC123":1.5}}"#.utf8))
        #expect(decoded.channelPlaybackSpeeds == ["UC123": 1.5])

        let legacy = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"playbackSpeed":1.25}"#.utf8))
        #expect(legacy.channelPlaybackSpeeds.isEmpty)
        #expect(legacy.playbackSpeed == 1.25)
    }
}
