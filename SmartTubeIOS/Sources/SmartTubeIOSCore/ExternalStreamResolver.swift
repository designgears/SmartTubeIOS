import Foundation

// MARK: - ExternalStreamResolver

/// The HLS URL to play for a Twitch or Kick live stream or past broadcast, asked right before
/// playing (Twitch's playback tokens expire within minutes).
public enum ExternalStreamResolver {
    public static func playbackURL(for video: Video) async throws -> URL {
        guard let target = ExternalID.parse(video.id), target.kind != .channel else {
            throw ExternalStreamError.unavailable("Not a Twitch or Kick video.")
        }
        switch target.platform {
        case .twitch: return try await TwitchClient.shared.playbackURL(for: target)
        case .kick: return try await KickClient.shared.playbackURL(for: target)
        case .youtube: throw ExternalStreamError.unavailable("Not a Twitch or Kick video.")
        }
    }
}
