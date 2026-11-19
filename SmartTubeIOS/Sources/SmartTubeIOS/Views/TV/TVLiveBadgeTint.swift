#if os(tvOS)
import UIKit

// MARK: - The player's LIVE tag in the app's live color

/// Recolors AVKit's own LIVE tags (beside the subtitle, and at the scrubber's live edge) from
/// the system pink to `color` (the stream's service LIVE color, `AppColor.live`). AVKit has no API for it: each tag is an
/// `AVUnifiedPlayerPlaybackStyleBadgeView` over a visual-effect view whose fill is a plain
/// background color. AVKit re-sets that color as the tag changes state, so each fill is
/// watched and recolored again — but only while it's the live pink (a tag showing something
/// else keeps its color). If a future tvOS builds the tag differently, it simply stays pink.
@MainActor
final class TVLiveBadgeTint {
    private var observations: [ObjectIdentifier: NSKeyValueObservation] = [:]
    /// Fills already given `color`, to repaint when the setting changes.
    private let tinted = NSHashTable<UIView>.weakObjects()

    var color = UIColor(AppColor.live()) {
        didSet {
            guard color != oldValue else { return }
            for fill in tinted.allObjects where fill.backgroundColor == oldValue {
                fill.backgroundColor = color
            }
        }
    }

    func apply(in root: UIView) {
        for fill in Self.badgeFills(in: root) where observations[ObjectIdentifier(fill)] == nil {
            recolor(fill)
            observations[ObjectIdentifier(fill)] = observe(fill)
        }
    }

    private func observe(_ fill: UIView) -> NSKeyValueObservation {
        fill.layer.observe(\.backgroundColor, options: [.new]) { [weak self, weak fill] _, _ in
            MainActor.assumeIsolated {
                guard let self, let fill else { return }
                self.recolor(fill)
            }
        }
    }

    private func recolor(_ fill: UIView) {
        guard let current = fill.backgroundColor, current != color,
            Self.isSystemLive(current, in: fill.traitCollection)
        else { return }
        fill.backgroundColor = color
        tinted.add(fill)
    }

    /// The system's live pink (or red, should it move back to it).
    private static func isSystemLive(_ color: UIColor, in traits: UITraitCollection) -> Bool {
        let resolved = color.resolvedColor(with: traits)
        return [UIColor.systemPink, .systemRed].contains { $0.resolvedColor(with: traits) == resolved }
    }

    /// The colored fill inside each badge's effect view.
    private static func badgeFills(in view: UIView) -> [UIView] {
        if NSStringFromClass(type(of: view)).contains("PlaybackStyleBadgeView") {
            return view.subviews.compactMap { $0 as? UIVisualEffectView }
                .flatMap(\.subviews).filter { $0.backgroundColor != nil }
        }
        return view.subviews.flatMap { badgeFills(in: $0) }
    }
}
#endif
