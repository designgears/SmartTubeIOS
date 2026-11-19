import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - TwitchAds

/// How Twitch's ads are kept off the screen. Twitch stitches ads into the stream on its side,
/// per playback session; what it does depends on the player type the playback token is asked
/// for (measured 2026-11-19, and the approach of TwitchAdSolutions' vaft):
///
/// - The website's `site` player gets a pre-roll; `popout` doesn't, at full quality.
/// - During an ad break every full-quality player type gets the ads, but `autoplay` and
///   `picture-by-picture` (360p at most) stay clean: the break plays at low quality instead.
public enum TwitchAds {
    /// The main stream's player type: no pre-roll, full quality.
    public static let playerType = "popout"
    /// Ad-free during breaks, 360p at most; tried in this order.
    public static let backupPlayerTypes = ["autoplay", "picture-by-picture"]
    /// The website's own player type (pre-rolls and all), when ad blocking is off.
    public static let sitePlayerType = "site"
    /// How often the main stream is checked for a break starting or ending.
    public static let pollInterval: Duration = .seconds(4)

    /// Ad markers in a media playlist (vaft's list, Nov 2026).
    static let signifiers = [
        "stitched-ad", "EXT-X-CUE-OUT", "twitch-stitched", #"EXT-X-DATERANGE:CLASS="twitch-maf-ad""#,
        #"EXT-X-DATERANGE:CLASS="twitch-trigger""#,
    ]
    /// Ad segments' URLs.
    static let adSegmentPaths = ["/adsquared/", "/_404/", "/processing"]

    /// Whether a media playlist carries ads: a marker, an ad segment URL, or a segment not
    /// titled `live` (Twitch titles stream segments `live`, ad segments `Amazon|…`).
    public static func hasAds(_ playlist: String) -> Bool {
        if signifiers.contains(where: playlist.contains) { return true }
        for line in playlist.split(whereSeparator: \.isNewline) {
            if line.hasPrefix("#EXTINF:") {
                let title = line.split(separator: ",", maxSplits: 1).dropFirst().first.map(String.init) ?? ""
                if !title.isEmpty, title != "live" { return true }
            } else if !line.hasPrefix("#"), adSegmentPaths.contains(where: line.contains) {
                return true
            }
        }
        return false
    }

    /// The variant to watch for breaks: the smallest video one (all variants of a session carry
    /// the same ads), so polling stays cheap.
    public static func watchedVariant(in multivariant: String) -> URL? {
        var best: (bandwidth: Int, url: URL)?
        var pendingBandwidth: Int?
        for line in multivariant.split(whereSeparator: \.isNewline).map(String.init) {
            if line.hasPrefix("#EXT-X-STREAM-INF:") {
                let isAudio = line.contains(#"VIDEO="audio_only""#) || !line.contains("RESOLUTION=")
                pendingBandwidth =
                    isAudio
                    ? nil : line.firstMatch(of: /BANDWIDTH=(\d+)/).flatMap { Int($0.output.1) } ?? Int.max
            } else if !line.hasPrefix("#"), let bandwidth = pendingBandwidth, let url = URL(string: line) {
                if best.map({ bandwidth < $0.bandwidth }) ?? true { best = (bandwidth, url) }
                pendingBandwidth = nil
            }
        }
        return best?.url
    }

    /// A playlist's text, nil on any failure.
    public static func fetch(_ url: URL) async -> String? {
        guard let (data, response) = try? await URLSession.shared.data(from: url),
            (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? false
        else { return nil }
        return String(bytes: data, encoding: .utf8)
    }
}
