import Foundation

// MARK: - Compact counts

/// "950", "1.5K", "18K", "1.5M", "125M", "1.4B" — one decimal below 10, none above, like
/// YouTube's own counts.
public func compactCount(_ value: Int) -> String {
    let units: [(threshold: Double, suffix: String)] = [(1e9, "B"), (1e6, "M"), (1e3, "K")]
    let number = Double(value)
    for unit in units where abs(number) >= unit.threshold {
        let scaled = number / unit.threshold
        // Truncate, never round up (18,999 → "18K"), as YouTube does.
        let text =
            scaled < 10
            ? String(format: "%.1f", (scaled * 10).rounded(.down) / 10)
            : String(Int(scaled.rounded(.down)))
        return text.replacingOccurrences(of: ".0", with: "") + unit.suffix
    }
    return String(value)
}

// MARK: - VideoDetails

/// What the watch page says about a video beyond the player response: when it was published,
/// exact views and likes, and its channel's subscribers and avatar. From the WEB `/next`.
public struct VideoDetails: Sendable, Codable, Equatable {
    /// Absolute publish date as YouTube writes it, e.g. "Nov 15, 2026".
    public var dateText: String?
    /// e.g. "9 hours ago".
    public var relativeDateText: String?
    public var viewCount: Int?
    public var likeCount: Int?
    public var subscriberCountText: String?
    public var channelAvatarURL: URL?

    public init(
        dateText: String? = nil, relativeDateText: String? = nil, viewCount: Int? = nil, likeCount: Int? = nil,
        subscriberCountText: String? = nil, channelAvatarURL: URL? = nil
    ) {
        self.dateText = dateText
        self.relativeDateText = relativeDateText
        self.viewCount = viewCount
        self.likeCount = likeCount
        self.subscriberCountText = subscriberCountText
        self.channelAvatarURL = channelAvatarURL
    }

    /// Reads `videoPrimaryInfoRenderer` / `videoSecondaryInfoRenderer` from a WEB `/next`
    /// response. Nil when neither is present (e.g. a TV-client response).
    public static func parse(next json: [String: Any]) -> VideoDetails? {
        let primary = firstValue(forKey: "videoPrimaryInfoRenderer", in: json) as? [String: Any]
        let secondary = firstValue(forKey: "videoSecondaryInfoRenderer", in: json) as? [String: Any]
        guard primary != nil || secondary != nil else { return nil }

        var details = VideoDetails()
        if let primary {
            details.dateText = text(primary["dateText"])
            details.relativeDateText = text(primary["relativeDateText"])
            let viewRenderer =
                (primary["viewCount"] as? [String: Any])?["videoViewCountRenderer"] as? [String: Any]
            // `originalViewCount` is "0" for many videos while the text has the real count
            // ("177,212 views"), so the text comes first and a zero is never trusted.
            details.viewCount =
                text(viewRenderer?["viewCount"]).flatMap { leadingNumber(in: $0) }.flatMap { $0 > 0 ? $0 : nil }
                ?? (viewRenderer?["originalViewCount"] as? String).flatMap { Int($0) }.flatMap { $0 > 0 ? $0 : nil }
            details.likeCount = likeCount(in: primary)
        }
        if let owner = (secondary?["owner"] as? [String: Any])?["videoOwnerRenderer"] as? [String: Any] {
            details.subscriberCountText = text(owner["subscriberCountText"])
            let thumbnails = (owner["thumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]]
            details.channelAvatarURL = thumbnails?.last.flatMap { $0["url"] as? String }.flatMap(URL.init(string:))
        }
        return details
    }

    /// The like button's accessibility text carries the exact count ("like this video along
    /// with 18,134 other people"); its title only the rounded one ("18K").
    private static func likeCount(in primary: [String: Any]) -> Int? {
        guard let likeButton = firstValue(forKey: "likeButtonViewModel", in: primary) else { return nil }
        if let accessibility = firstValue(forKey: "accessibilityText", in: likeButton) as? String,
            let count = leadingNumber(in: accessibility)
        {
            return count
        }
        return nil
    }

    /// The first whole number in `text`, any thousands separator: "1,585,288 views" → 1585288.
    /// Only for full counts — "1.5M" would read as 15.
    static func leadingNumber(in text: String) -> Int? {
        guard let range = text.range(of: #"\d[\d,.\u{00A0} ]*\d|\d"#, options: .regularExpression) else {
            return nil
        }
        return Int(text[range].filter(\.isNumber))
    }

    private static func text(_ value: Any?) -> String? {
        guard let dict = value as? [String: Any] else { return nil }
        if let simple = dict["simpleText"] as? String { return simple }
        let runs = (dict["runs"] as? [[String: Any]])?.compactMap { $0["text"] as? String }.joined()
        return runs?.isEmpty == false ? runs : nil
    }

    /// Depth-first search for the first value stored under `key`.
    private static func firstValue(forKey key: String, in value: Any) -> Any? {
        if let dict = value as? [String: Any] {
            if let hit = dict[key] { return hit }
            for child in dict.values {
                if let hit = firstValue(forKey: key, in: child) { return hit }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let hit = firstValue(forKey: key, in: child) { return hit }
            }
        }
        return nil
    }
}

// MARK: - Return YouTube Dislike

/// Likes and (estimated) dislikes from returnyoutubedislike.com — YouTube hides dislikes.
public struct VideoVotes: Sendable, Equatable {
    public var likes: Int
    public var dislikes: Int

    public init(likes: Int, dislikes: Int) {
        self.likes = likes
        self.dislikes = dislikes
    }

    /// Parses `GET https://returnyoutubedislikeapi.com/votes?videoId=…`.
    public static func parse(_ data: Data) -> VideoVotes? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let likes = json["likes"] as? Int, let dislikes = json["dislikes"] as? Int
        else { return nil }
        return VideoVotes(likes: likes, dislikes: dislikes)
    }
}

/// Fetches `VideoVotes`, remembering recent answers so reopening a video doesn't ask again.
public actor ReturnYouTubeDislike {
    public static let shared = ReturnYouTubeDislike()

    private var cache: [String: VideoVotes] = [:]
    private var order: [String] = []
    private static let maxCached = 100

    public func votes(for videoId: String) async -> VideoVotes? {
        if let cached = cache[videoId] { return cached }
        var components = URLComponents(string: "https://returnyoutubedislikeapi.com/votes")
        components?.queryItems = [URLQueryItem(name: "videoId", value: videoId)]
        guard let url = components?.url else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
            (response as? HTTPURLResponse)?.statusCode == 200,
            let votes = VideoVotes.parse(data)
        else { return nil }
        cache[videoId] = votes
        order.append(videoId)
        if order.count > Self.maxCached { cache.removeValue(forKey: order.removeFirst()) }
        return votes
    }
}
