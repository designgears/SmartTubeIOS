import AVFoundation
import VideoToolbox

/// What the current device can decode, for choosing between YouTube's codec ladders.
enum VideoCodecSupport {
    /// True when VP9 is hardware-decoded here and AVFoundation accepts VP9 in fragmented
    /// MP4 — the form YouTube's HLS masters use for their 1440p/2160p tiers. Always false in
    /// the Simulator, which cannot decode VP9.
    static let vp9HLS: Bool = {
        #if targetEnvironment(simulator)
        return false
        #else
        guard VTIsHardwareDecodeSupported(kCMVideoCodecType_VP9) else { return false }
        return AVURLAsset.isPlayableExtendedMIMEType("video/mp4; codecs=\"vp09.00.50.08\"")
        #endif
    }()
}
