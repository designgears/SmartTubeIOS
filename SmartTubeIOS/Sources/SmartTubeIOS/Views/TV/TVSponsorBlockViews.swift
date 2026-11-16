#if os(tvOS)
import SmartTubeIOSCore
import SwiftUI
import UIKit

// MARK: - SponsorBlock segments on the scrubber

/// SponsorBlock segments drawn over the native scrubber's track. It lives inside
/// AVPlayerViewController's own transport bar (see `attach(toTransportBarIn:)`) and fades
/// with the bar's track, in the same animation — nothing has to guess when the bar is up.
/// AVKit has no public API for annotating the bar (interstitial time ranges are treated as
/// ad breaks: they collapse the timeline and restart the clock).
final class TVSponsorSegmentStrip: UIView {
    /// The track's own thickness, so segments cover it exactly.
    private static let height: CGFloat = 13

    private var segments: [SponsorSegment] = []
    private var duration: TimeInterval = 0
    /// The track container whose opacity the strip copies.
    private weak var fadingTrack: UIView?
    private var fadeObservation: NSKeyValueObservation?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        autoresizingMask = [.flexibleWidth, .flexibleBottomMargin]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func update(segments: [SponsorSegment], duration: TimeInterval) {
        let drawable = segments.filter { $0.category != .poiHighlight && $0.end > $0.start }
        guard drawable != self.segments || duration != self.duration else { return }
        self.segments = drawable
        self.duration = duration
        drawSegments()
    }

    /// Puts the strip into the transport bar, if tvOS has created it. Returns whether it's in.
    @discardableResult
    func attach(toTransportBarIn root: UIView) -> Bool {
        guard let track = Self.fadingTrack(in: root), let bar = Self.transportBar(containing: track) else {
            return false
        }
        if superview !== bar { bar.addSubview(self) }
        if fadingTrack !== track { follow(track) }
        let height = min(Self.height, bar.bounds.height)
        let target = CGRect(
            x: 0, y: (bar.bounds.height - height) / 2, width: bar.bounds.width, height: height)
        if frame != target {
            frame = target
            drawSegments()
        }
        return true
    }

    /// Copies the track's opacity. AVKit fades it inside an animation block, and the copy is
    /// made synchronously from the KVO callback — inside that same block — so the strip fades
    /// with the same timing and curve.
    private func follow(_ track: UIView) {
        fadingTrack = track
        alpha = track.alpha
        fadeObservation = track.layer.observe(\.opacity, options: [.new]) { [weak self] layer, _ in
            let opacity = CGFloat(layer.opacity)
            MainActor.assumeIsolated { self?.alpha = opacity }
        }
    }

    /// AVKit's transport bar (`AVNowPlayingTransportBar` on tvOS 26), which spans the track.
    private static func transportBar(containing track: UIView) -> UIView? {
        var view = track.superview
        while let current = view {
            if NSStringFromClass(type(of: current)).contains("TransportBar") { return current }
            view = current.superview
        }
        return nil
    }

    /// The part of AVKit's transport bar that fades out when the bar hides — the container
    /// holding its interstitial-marker view. The bar view itself is drawn through a portal
    /// that ignores its own hidden state, and the container clips to the track, so the strip
    /// is a subview of the bar and copies this container's opacity.
    private static func fadingTrack(in view: UIView) -> UIView? {
        if NSStringFromClass(type(of: view)).contains("TransportBarInterstitialView") { return view.superview }
        for subview in view.subviews {
            if let found = fadingTrack(in: subview) { return found }
        }
        return nil
    }

    /// Drawn directly rather than in `layoutSubviews`: AVKit's bar doesn't give its subviews
    /// a layout pass.
    private func drawSegments() {
        layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        guard duration > 0, bounds.width > 0 else { return }
        let width = bounds.width
        for segment in segments {
            let start = max(0, min(segment.start / duration, 1))
            let end = max(start, min(segment.end / duration, 1))
            let piece = CALayer()
            piece.frame = CGRect(x: start * width, y: 0, width: max(3, (end - start) * width), height: bounds.height)
            piece.backgroundColor = UIColor(segment.category.color).withAlphaComponent(0.9).cgColor
            // Flat edges, like a stretch of the bar; an end that reaches the bar's own rounded
            // end is rounded to match.
            var corners: CACornerMask = []
            if start * width < 1 { corners.formUnion([.layerMinXMinYCorner, .layerMinXMaxYCorner]) }
            if (1 - end) * width < 1 { corners.formUnion([.layerMaxXMinYCorner, .layerMaxXMaxYCorner]) }
            piece.cornerRadius = corners.isEmpty ? 0 : bounds.height / 2
            piece.maskedCorners = corners
            layer.addSublayer(piece)
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
