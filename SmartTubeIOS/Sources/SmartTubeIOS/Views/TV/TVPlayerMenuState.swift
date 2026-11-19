#if os(tvOS)
import SmartTubeIOSCore
import SwiftUI

// MARK: - Menu state / actions

/// Value snapshot of everything the transport-bar menus show. Menus are rebuilt only when
/// this changes (it deliberately excludes the playback clock).
struct TVPlayerMenuState: Equatable {
    struct CaptionOption: Equatable {
        let id: String
        let name: String
    }
    struct ChapterOption: Equatable {
        let title: String
        let start: TimeInterval
    }

    var formats: [VideoFormat]
    var selectedFormatID: UUID?
    var captions: [CaptionOption]
    var selectedCaptionID: String?
    var speed: Double
    var isLiked: Bool
    var isDisliked: Bool
    var chapters: [ChapterOption]
    var hasNext: Bool
    var hasPrevious: Bool
    var skipLabel: String?
    var hasChannel: Bool
    /// "Channel · 1.5M views · 9 hours ago" — the line under the title in the transport bar.
    var subtitle: String
    /// Twitch and Kick have no likes, and no YouTube formats to pick from.
    var platform: StreamPlatform = .youtube
    /// Twitch and Kick live streams: their chat can be shown beside the video.
    var hasChat = false
    var showsChat = false
}

/// What the chat panel shows: this video's chat, when it's switched on.
struct ChatKey: Equatable {
    let video: Video
    let shown: Bool

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.video.id == rhs.video.id && lhs.shown == rhs.shown }
}

struct TVPlayerActions {
    var selectFormat: (VideoFormat?) -> Void
    var selectCaption: (String?) -> Void
    var setSpeed: (Double) -> Void
    var like: () -> Void
    var dislike: () -> Void
    var skipSegment: () -> Void
    var next: () -> Void
    var previous: () -> Void
    var seek: (TimeInterval) -> Void
    var playVideo: (Video) -> Void
    var openChannel: () -> Void
    var toggleChat: () -> Void = {}
}
#endif
