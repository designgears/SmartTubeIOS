import Testing

@testable import SmartTubeIOSCore

@Suite("HLS multivariant playlist — dropping playlists that don't load")
struct HLSVariantPruningTests {
    private let multivariant = """
        #EXTM3U
        #EXT-X-INDEPENDENT-SEGMENTS
        #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="233",NAME="Default",DEFAULT=YES,URI="audio-233.m3u8"
        #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="234",NAME="Default",DEFAULT=YES,URI="audio-234.m3u8"
        #EXT-X-STREAM-INF:BANDWIDTH=300000,RESOLUTION=426x240,CODECS="avc1.4D4015,mp4a.40.5",AUDIO="233"
        itag-229.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=1500000,RESOLUTION=1280x720,CODECS="avc1.4D401F,mp4a.40.2",AUDIO="234"
        itag-232.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=4000000,RESOLUTION=1920x1080,CODECS="avc1.640028,mp4a.40.2",AUDIO="234"
        itag-270.m3u8
        """

    @Test func listsVariantAndRenditionPlaylists() {
        #expect(
            Set(hlsMultivariantPlaylistURIs(multivariant))
                == ["audio-233.m3u8", "audio-234.m3u8", "itag-229.m3u8", "itag-232.m3u8", "itag-270.m3u8"])
    }

    /// The 240p variant 404s (seen on real videos): it goes, the rest stay intact.
    @Test func dropsAVariantThatDoesNotLoad() {
        let pruned = removingHLSPlaylists(["itag-229.m3u8"], from: multivariant)

        #expect(!pruned.contains("itag-229.m3u8"))
        #expect(!pruned.contains("RESOLUTION=426x240"))
        #expect(pruned.contains("itag-232.m3u8"))
        #expect(pruned.contains("itag-270.m3u8"))
        #expect(pruned.contains("audio-233.m3u8"), "renditions are only dropped when they themselves fail")
        #expect(hlsMultivariantPlaylistURIs(pruned).count == 4)
    }

    /// A variant whose only audio rendition fails can't play, so it goes too.
    @Test func dropsVariantsThatLostTheirAudio() {
        let pruned = removingHLSPlaylists(["audio-233.m3u8"], from: multivariant)

        #expect(!pruned.contains("audio-233.m3u8"))
        #expect(!pruned.contains("itag-229.m3u8"))
        #expect(pruned.contains("itag-232.m3u8"))
        #expect(pruned.contains("itag-270.m3u8"))
    }

    @Test func nothingUnavailableLeavesThePlaylistAsIs() {
        #expect(removingHLSPlaylists([], from: multivariant) == multivariant)
    }
}
