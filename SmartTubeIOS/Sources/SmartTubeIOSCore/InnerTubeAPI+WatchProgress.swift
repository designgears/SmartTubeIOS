import Foundation

// MARK: - Resume bar

extension InnerTubeAPI {
    /// The resume bar's percentage anywhere under `value`: `startPercent` (view-model
    /// overlays) or `percentDurationWatched` (renderer overlays).
    static func resumePercent(in value: Any) -> Double? {
        if let dict = value as? [String: Any] {
            for key in ["startPercent", "percentDurationWatched"] {
                if let number = dict[key] as? NSNumber { return number.doubleValue }
            }
            for child in dict.values {
                if let found = resumePercent(in: child) { return found }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let found = resumePercent(in: child) { return found }
            }
        }
        return nil
    }
}
