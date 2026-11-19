import Foundation

// MARK: - StreamingSettings

/// Settings › Twitch & Kick: ad blocking and live chat.
public struct StreamingSettings: Codable, Equatable, Sendable {
    /// Skip Twitch's pre-roll ads, and during an ad break play Twitch's ad-free low-quality
    /// copy of the stream until the break ends (see `TwitchAds`).
    public var blockTwitchAds = true
    /// Emote images in chat instead of their names.
    public var chatEmotes = true
    /// 7TV, BetterTTV and FrankerFaceZ emotes as well as the service's own.
    public var thirdPartyEmotes = true

    public init() {}

    /// Missing keys (settings saved before them) take the defaults.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = StreamingSettings()
        blockTwitchAds = try container.decodeIfPresent(Bool.self, forKey: .blockTwitchAds) ?? defaults.blockTwitchAds
        chatEmotes = try container.decodeIfPresent(Bool.self, forKey: .chatEmotes) ?? defaults.chatEmotes
        thirdPartyEmotes =
            try container.decodeIfPresent(Bool.self, forKey: .thirdPartyEmotes) ?? defaults.thirdPartyEmotes
    }
}
