import Foundation

// MARK: - Quality label for a picture size

/// The YouTube quality name ("1080p") for a decoded picture size, for showing what Auto is
/// playing. Goes by the picture's long side against the 16:9 widths YouTube encodes at, so a
/// cinematic 1920×800 is still 1080p and a vertical 1080×1920 is 1080p too. Nil without a size.
public func qualityName(width: Double, height: Double) -> String? {
    let longSide = max(width, height)
    guard longSide > 0 else { return nil }
    // (16:9 width, name), largest first; a little slack for encoders that crop a few pixels.
    let ladder: [(Double, String)] = [
        (7680, "4320p"), (3840, "2160p"), (2560, "1440p"), (1920, "1080p"), (1280, "720p"),
        (854, "480p"), (640, "360p"), (426, "240p"),
    ]
    return ladder.first { longSide >= $0.0 * 0.95 }?.1 ?? "144p"
}
