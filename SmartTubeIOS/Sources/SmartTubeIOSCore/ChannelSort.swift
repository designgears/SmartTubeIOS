import Foundation

// MARK: - ChannelSort

/// The order of the Channels page. Live channels always come first, in this same order.
public enum ChannelSort: String, Codable, CaseIterable, Sendable {
    /// YouTube's: channels with new videos first, then the rest A–Z.
    case youTube
    case alphabetical
    case reverseAlphabetical

    public var title: String {
        switch self {
        case .youTube: "New Videos First"
        case .alphabetical: "A–Z"
        case .reverseAlphabetical: "Z–A"
        }
    }

    public func sorted(_ channels: [Channel], isLive: (Channel) -> Bool) -> [Channel] {
        let ordered: [Channel] =
            switch self {
            case .youTube: channels
            case .alphabetical: channels.sorted { Self.precedes($0, $1) }
            case .reverseAlphabetical: channels.sorted { Self.precedes($1, $0) }
            }
        let live = ordered.filter(isLive)
        return live + ordered.filter { !isLive($0) }
    }

    private static func precedes(_ lhs: Channel, _ rhs: Channel) -> Bool {
        lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }
}
