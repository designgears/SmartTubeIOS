import Foundation

// MARK: - Live

extension InnerTubeAPI {
    /// Whether a player response's video is live right now. `isLiveContent` stays true after a
    /// stream ends (its replay is a regular video), so it only counts alongside a zero length
    /// and not upcoming — for a client that leaves `isLive` out.
    static func isLiveNow(_ videoDetails: [String: Any]?) -> Bool {
        if let isLive = videoDetails?["isLive"] as? Bool { return isLive }
        let isLiveContent = videoDetails?["isLiveContent"] as? Bool ?? false
        let length = (videoDetails?["lengthSeconds"] as? String).flatMap { Double($0) } ?? 0
        let isUpcoming = videoDetails?["isUpcoming"] as? Bool ?? false
        return isLiveContent && length == 0 && !isUpcoming
    }
}
