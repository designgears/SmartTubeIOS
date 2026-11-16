#if os(tvOS)
import SmartTubeIOSCore
import SwiftUI

// MARK: - SponsorBlock segments on the scrubber

/// Colours SponsorBlock segments onto the native scrubber while the transport bar is up.
/// AVPlayerViewController offers no API to annotate its progress bar (interstitial
/// ranges are treated as ad breaks: they collapse the timeline and restart the clock),
/// so the segments are drawn over it, aligned to where tvOS lays the bar out.
struct TVSponsorSegmentsTrack: View {
    let segments: [SponsorSegment]
    let duration: TimeInterval
    let isVisible: Bool

    /// The native scrubber's track in screen points (1920×1080), measured in the tvOS simulator.
    private static let trackX: ClosedRange<CGFloat> = 80...1840
    private static let trackMidY: CGFloat = 909.5
    private static let segmentHeight: CGFloat = 13

    var body: some View {
        let drawable = segments.filter { $0.category != .poiHighlight && $0.end > $0.start }
        if isVisible, duration > 0, !drawable.isEmpty {
            let width = Self.trackX.upperBound - Self.trackX.lowerBound
            ZStack(alignment: .topLeading) {
                ForEach(drawable) { segment in
                    let start = max(0, min(segment.start / duration, 1))
                    let end = max(start, min(segment.end / duration, 1))
                    // Flat edges, like a stretch of the scrubber; only an end that reaches the
                    // track's own (rounded) end is rounded to match it.
                    let radius = Self.segmentHeight / 2
                    let roundsStart = start * width < 1
                    let roundsEnd = (1 - end) * width < 1
                    UnevenRoundedRectangle(
                        topLeadingRadius: roundsStart ? radius : 0, bottomLeadingRadius: roundsStart ? radius : 0,
                        bottomTrailingRadius: roundsEnd ? radius : 0, topTrailingRadius: roundsEnd ? radius : 0,
                        style: .continuous
                    )
                    .fill(segment.category.color.opacity(0.9))
                    .frame(width: max(4, (end - start) * width), height: Self.segmentHeight)
                    .offset(
                        x: Self.trackX.lowerBound + start * width,
                        y: Self.trackMidY - Self.segmentHeight / 2)
                }
            }
            .frame(width: 1920, height: 1080, alignment: .topLeading)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }
}

// MARK: - SponsorBlock labels

extension SponsorSegment.Category {
    var tvLabel: String {
        switch self {
        case .sponsor: return "Sponsor"
        case .selfPromo: return "Self-Promo"
        case .interaction: return "Reminder"
        case .intro: return "Intro"
        case .outro: return "Outro"
        case .preview: return "Preview"
        case .filler: return "Filler"
        case .musicOfftopic: return "Non-Music"
        case .poiHighlight: return "to Highlight"
        }
    }
}
#endif
