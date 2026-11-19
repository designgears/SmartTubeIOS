import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - ChatPart

/// A run of a chat message: text, or an emote drawn as a picture (its name when pictures are off
/// or not loaded yet).
public enum ChatPart: Hashable, Sendable {
    case text(String)
    case emote(name: String, url: URL)

    /// What the part says as text.
    public var plain: String {
        switch self {
        case .text(let text): text
        case .emote(let name, _): name
        }
    }
}

// MARK: - Native emotes

enum NativeEmotes {
    /// Twitch's own emote picture (the still one, for animated emotes).
    static func twitchURL(id: String) -> URL? {
        URL(string: "https://static-cdn.jtvnw.net/emoticons/v2/\(id)/static/dark/2.0")
    }

    static func kickURL(id: String) -> URL? {
        URL(string: "https://files.kick.com/emotes/\(id)/fullsize")
    }

    /// Twitch IRC's `emotes` tag (`25:0-4,12-16/1902:6-10`, code-point positions) applied to
    /// the message text.
    static func twitchParts(_ text: String, emotesTag: String?) -> [ChatPart] {
        guard let emotesTag, !emotesTag.isEmpty else { return [.text(text)] }
        var ranges: [(range: ClosedRange<Int>, id: String)] = []
        for entry in emotesTag.split(separator: "/") {
            let pair = entry.split(separator: ":", maxSplits: 1)
            guard pair.count == 2 else { continue }
            for span in pair[1].split(separator: ",") {
                let bounds = span.split(separator: "-").compactMap { Int($0) }
                if bounds.count == 2, bounds[0] <= bounds[1] { ranges.append((bounds[0]...bounds[1], String(pair[0]))) }
            }
        }
        let scalars = Array(text.unicodeScalars)
        var parts: [ChatPart] = []
        var cursor = 0
        for (range, id) in ranges.sorted(by: { $0.range.lowerBound < $1.range.lowerBound })
        where range.lowerBound >= cursor && range.upperBound < scalars.count {
            if range.lowerBound > cursor { parts.append(.text(string(scalars[cursor..<range.lowerBound]))) }
            let name = string(scalars[range])
            if let url = twitchURL(id: id) {
                parts.append(.emote(name: name, url: url))
            } else {
                parts.append(.text(name))
            }
            cursor = range.upperBound + 1
        }
        if cursor < scalars.count { parts.append(.text(string(scalars[cursor...]))) }
        return parts.isEmpty ? [.text(text)] : parts
    }

    /// Kick's `[emote:5748001:KEKW]` codes as pictures.
    static func kickParts(_ text: String) -> [ChatPart] {
        var parts: [ChatPart] = []
        var rest = Substring(text)
        while let match = rest.firstMatch(of: /\[emote:(\d+):([^\]]+)\]/) {
            if match.range.lowerBound > rest.startIndex { parts.append(.text(String(rest[..<match.range.lowerBound]))) }
            let name = String(match.output.2)
            if let url = kickURL(id: String(match.output.1)) { parts.append(.emote(name: name, url: url)) }
            rest = rest[match.range.upperBound...]
        }
        if !rest.isEmpty { parts.append(.text(String(rest))) }
        return parts.isEmpty ? [.text(text)] : parts
    }

    private static func string(_ scalars: ArraySlice<Unicode.Scalar>) -> String {
        var text = ""
        text.unicodeScalars.append(contentsOf: scalars)
        return text
    }
}

// MARK: - Community emotes

/// 7TV, BetterTTV and FrankerFaceZ emotes for a channel: name → picture. Channel sets win over
/// global ones; 7TV over BetterTTV over FFZ. BetterTTV and FFZ are Twitch-only.
public struct EmoteCatalog: Sendable, Equatable {
    public private(set) var emotes: [String: URL] = [:]

    public init(emotes: [String: URL] = [:]) {
        self.emotes = emotes
    }

    public var isEmpty: Bool { emotes.isEmpty }

    /// Words of the text parts that name an emote become emotes.
    public func apply(_ parts: [ChatPart]) -> [ChatPart] {
        guard !emotes.isEmpty else { return parts }
        var result: [ChatPart] = []
        for part in parts {
            guard case .text(let text) = part else {
                result.append(part)
                continue
            }
            var pending = ""
            for (index, word) in text.split(separator: " ", omittingEmptySubsequences: false).enumerated() {
                if index > 0 { pending += " " }
                if let url = emotes[String(word)] {
                    if !pending.isEmpty { result.append(.text(pending)) }
                    pending = ""
                    result.append(.emote(name: String(word), url: url))
                } else {
                    pending += word
                }
            }
            if !pending.isEmpty { result.append(.text(pending)) }
        }
        return result
    }

    /// Lower-priority sets first: later ones overwrite names.
    mutating func merge(_ other: [String: URL]) {
        emotes.merge(other) { _, new in new }
    }

    /// Everything for a Twitch channel (by its numeric user id) or a Kick channel (by its user id).
    public static func load(platform: StreamPlatform, userId: String) async -> EmoteCatalog {
        async let ffzGlobal = platform == .twitch ? fetch(ffzGlobalURL, parse: parseFFZ) : [:]
        async let ffzRoom = platform == .twitch ? fetch(ffzRoomURL(userId), parse: parseFFZ) : [:]
        async let bttvGlobal = platform == .twitch ? fetch(bttvGlobalURL, parse: parseBTTV) : [:]
        async let bttvChannel = platform == .twitch ? fetch(bttvChannelURL(userId), parse: parseBTTV) : [:]
        async let sevenGlobal = fetch(sevenTVGlobalURL, parse: parseSevenTV)
        async let sevenChannel = fetch(sevenTVUserURL(platform, userId), parse: parseSevenTV)
        var catalog = EmoteCatalog()
        for set in await [ffzGlobal, ffzRoom, bttvGlobal, bttvChannel, sevenGlobal, sevenChannel] { catalog.merge(set) }
        return catalog
    }

    // MARK: Sources

    static let sevenTVGlobalURL = URL(string: "https://7tv.io/v3/emote-sets/global")
    static let bttvGlobalURL = URL(string: "https://api.betterttv.net/3/cached/emotes/global")
    static let ffzGlobalURL = URL(string: "https://api.frankerfacez.com/v1/set/global")

    static func sevenTVUserURL(_ platform: StreamPlatform, _ userId: String) -> URL? {
        URL(string: "https://7tv.io/v3/users/\(platform == .kick ? "kick" : "twitch")/\(userId)")
    }

    static func bttvChannelURL(_ userId: String) -> URL? {
        URL(string: "https://api.betterttv.net/3/cached/users/twitch/\(userId)")
    }

    static func ffzRoomURL(_ userId: String) -> URL? {
        URL(string: "https://api.frankerfacez.com/v1/room/id/\(userId)")
    }

    private static func fetch(_ url: URL?, parse: @Sendable (Any) -> [String: URL]) async -> [String: URL] {
        guard let url, let (data, _) = try? await URLSession.shared.data(from: url),
            let json = try? JSONSerialization.jsonObject(with: data)
        else { return [:] }
        return parse(json)
    }

    /// A 7TV emote set (`{"emotes": [...]}`) or user (`{"emote_set": {"emotes": [...]}}`); the
    /// still 2x picture.
    static func parseSevenTV(_ json: Any) -> [String: URL] {
        guard let root = json as? [String: Any] else { return [:] }
        let list = (root["emotes"] ?? (root["emote_set"] as? [String: Any])?["emotes"]) as? [[String: Any]] ?? []
        var emotes: [String: URL] = [:]
        for emote in list {
            guard let name = emote["name"] as? String,
                let host = (emote["data"] as? [String: Any])?["host"] as? [String: Any],
                let base = host["url"] as? String
            else { continue }
            let files = host["files"] as? [[String: Any]] ?? []
            let twoX = files.first { ($0["name"] as? String)?.hasPrefix("2x") == true }
            let file = (twoX?["static_name"] ?? twoX?["name"]) as? String ?? "2x.webp"
            if let url = URL(string: (base.hasPrefix("//") ? "https:" : "") + base + "/" + file) { emotes[name] = url }
        }
        return emotes
    }

    /// BetterTTV global (`[...]`) or channel (`{"channelEmotes": [...], "sharedEmotes": [...]}`).
    static func parseBTTV(_ json: Any) -> [String: URL] {
        let list: [[String: Any]]
        if let array = json as? [[String: Any]] {
            list = array
        } else if let root = json as? [String: Any] {
            list = (root["channelEmotes"] as? [[String: Any]] ?? []) + (root["sharedEmotes"] as? [[String: Any]] ?? [])
        } else {
            return [:]
        }
        var emotes: [String: URL] = [:]
        for emote in list {
            guard let code = emote["code"] as? String, let id = emote["id"] as? String,
                let url = URL(string: "https://cdn.betterttv.net/emote/\(id)/2x")
            else { continue }
            emotes[code] = url
        }
        return emotes
    }

    /// FrankerFaceZ room or global set answer: `{"sets": {"id": {"emoticons": [...]}}}`.
    static func parseFFZ(_ json: Any) -> [String: URL] {
        guard let sets = (json as? [String: Any])?["sets"] as? [String: Any] else { return [:] }
        var emotes: [String: URL] = [:]
        for case let set as [String: Any] in sets.values {
            for emote in set["emoticons"] as? [[String: Any]] ?? [] {
                guard let name = emote["name"] as? String, let urls = emote["urls"] as? [String: Any],
                    let link = (urls["2"] ?? urls["1"]) as? String,
                    let url = URL(string: (link.hasPrefix("//") ? "https:" : "") + link)
                else { continue }
                emotes[name] = url
            }
        }
        return emotes
    }
}
