import Foundation

// MARK: - StreamPlatform

/// Where a video or channel comes from. Twitch and Kick items reuse `Video` and `Channel`
/// with a prefixed id (`ExternalID`), so they never collide with YouTube ids in the history,
/// watched, cache or state stores; anything unprefixed is YouTube.
public enum StreamPlatform: String, Sendable, Codable, CaseIterable {
    case youtube
    case twitch
    case kick

    public init(id: String) {
        self = ExternalID.parse(id)?.platform ?? .youtube
    }

    public var title: String {
        switch self {
        case .youtube: "YouTube"
        case .twitch: "Twitch"
        case .kick: "Kick"
        }
    }
}

// MARK: - ExternalID

/// Ids for Twitch and Kick items: `twitch:live:<login>`, `twitch:vod:<id>`, `twitch:<login>`
/// (channel); the same for `kick` with the channel slug and the video's uuid.
public enum ExternalID {
    public enum Kind: Equatable, Sendable {
        /// The channel's live stream.
        case live
        /// A past broadcast.
        case vod
        case channel
    }

    public struct Parsed: Equatable, Sendable {
        public let platform: StreamPlatform
        public let kind: Kind
        /// Twitch login / Kick slug for `.live` and `.channel`; the video id / uuid for `.vod`.
        public let key: String
    }

    public static func live(_ platform: StreamPlatform, _ channel: String) -> String {
        "\(platform.rawValue):live:\(channel.lowercased())"
    }

    public static func vod(_ platform: StreamPlatform, _ id: String) -> String {
        "\(platform.rawValue):vod:\(id)"
    }

    public static func channel(_ platform: StreamPlatform, _ channel: String) -> String {
        "\(platform.rawValue):\(channel.lowercased())"
    }

    public static func parse(_ id: String) -> Parsed? {
        let parts = id.split(separator: ":", maxSplits: 2).map(String.init)
        guard parts.count >= 2, let platform = StreamPlatform(rawValue: parts[0]), platform != .youtube else {
            return nil
        }
        if parts.count == 3, !parts[2].isEmpty {
            switch parts[1] {
            case "live": return Parsed(platform: platform, kind: .live, key: parts[2])
            case "vod": return Parsed(platform: platform, kind: .vod, key: parts[2])
            default: return nil
            }
        }
        return parts.count == 2 && !parts[1].isEmpty ? Parsed(platform: platform, kind: .channel, key: parts[1]) : nil
    }
}

public extension Video {
    var platform: StreamPlatform { StreamPlatform(id: id) }
    /// A Twitch or Kick stream or past broadcast: played straight from its HLS, without
    /// YouTube's extras (SponsorBlock, related videos, history, likes).
    var isExternal: Bool { platform != .youtube }
}

public extension Channel {
    var platform: StreamPlatform { StreamPlatform(id: id) }
}
