import Foundation
import Testing

@testable import SmartTubeIOSCore

@Suite("StreamURLRewriter")
struct StreamURLRewriterTests {
    private let plainURL = "https://rr1.googlevideo.com/videoplayback?expire=1&sparams=expire%2Cn&n=SCRAMBLED&sig=abc"

    private var cipheredFormat: [String: Any] {
        let inner = "https://rr1.googlevideo.com/videoplayback?expire=1&n=CIPHERN&sparams=expire%2Cn"
        let encodedInner = inner.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? inner
        return ["itag": 137, "signatureCipher": "s=RAW%3DSIG&sp=sig&url=\(encodedInner)"]
    }

    @Test func collectsSigAndNChallenges() {
        let formats: [[String: Any]] = [["itag": 18, "url": plainURL], cipheredFormat]
        let challenges = StreamURLRewriter.challenges(in: formats, includeN: true)
        #expect(challenges.sig == ["RAW=SIG"])
        #expect(challenges.n == ["SCRAMBLED", "CIPHERN"])
    }

    @Test func skipsNForJSLessClients() {
        let challenges = StreamURLRewriter.challenges(in: [["itag": 18, "url": plainURL]], includeN: false)
        #expect(challenges.isEmpty)
    }

    @Test func rewritesNWithoutTouchingOtherParams() throws {
        let solutions = StreamChallengeSolutions(n: ["SCRAMBLED": "solved_n"])
        let url = try #require(
            StreamURLRewriter.resolvedURL(for: ["url": plainURL], solutions: solutions, includeN: true))
        #expect(url.absoluteString == plainURL.replacingOccurrences(of: "n=SCRAMBLED", with: "n=solved_n"))
    }

    @Test func leavesNAloneForJSLessClients() throws {
        let solutions = StreamChallengeSolutions(n: ["SCRAMBLED": "solved_n"])
        let url = try #require(
            StreamURLRewriter.resolvedURL(for: ["url": plainURL], solutions: solutions, includeN: false))
        #expect(url.absoluteString == plainURL)
    }

    @Test func decipheredFormatGetsSigParamAndN() throws {
        let solutions = StreamChallengeSolutions(n: ["CIPHERN": "nn"], sig: ["RAW=SIG": "SOLVED=SIG"])
        let url = try #require(
            StreamURLRewriter.resolvedURL(for: cipheredFormat, solutions: solutions, includeN: true))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.first { $0.name == "sig" }?.value == "SOLVED=SIG")
        #expect(items.first { $0.name == "n" }?.value == "nn")
        #expect(url.absoluteString.contains("sparams=expire%2Cn"))
    }

    @Test func unsolvedCipherYieldsNoURL() {
        #expect(StreamURLRewriter.resolvedURL(for: cipheredFormat, solutions: .empty, includeN: true) == nil)
    }

    // MARK: HLS

    private let multivariantPlaylist = """
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=1,RESOLUTION=1280x720
        https://manifest.googlevideo.com/api/manifest/hls_playlist/expire/1/n/AAA/itag/22/file/index.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=2,RESOLUTION=1920x1080
        https://manifest.googlevideo.com/api/manifest/hls_playlist/expire/1/n/AAA/itag/37/file/index.m3u8
        """

    @Test func findsDistinctHLSNValues() {
        #expect(StreamURLRewriter.hlsNChallenges(in: multivariantPlaylist) == ["AAA"])
        #expect(StreamURLRewriter.hlsNChallenges(in: "#EXTM3U\nhttps://x/videoplayback/id/1/file/seg.ts").isEmpty)
    }

    @Test func rewritesEveryHLSNOccurrence() {
        let out = StreamURLRewriter.replacingHLSN(in: multivariantPlaylist, solutions: ["AAA": "zz"])
        #expect(!out.contains("/n/AAA/"))
        #expect(out.components(separatedBy: "/n/zz/").count == 3)
    }
}
