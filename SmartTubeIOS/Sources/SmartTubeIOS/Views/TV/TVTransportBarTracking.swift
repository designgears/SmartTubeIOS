#if os(tvOS)
import AVKit
import SmartTubeIOSCore
import UIKit

// MARK: - SponsorBlock strip in the transport bar

// The strip is a subview of AVKit's own transport bar and fades with its track
// (`TVSponsorSegmentStrip`). The only job here is getting it in: tvOS may build the bar
// only when it first appears (a remote press or touch), and may rebuild it later, so the
// strip is re-attached after any remote interaction and whenever the bar reports a change.
extension TVNativePlayer.Coordinator {
    func installSegmentStrip(on view: UIView) {
        // Observe only (`shouldRecognizeSimultaneouslyWith`), never consume input.
        let presses = UILongPressGestureRecognizer(target: self, action: #selector(remoteTouched))
        presses.minimumPressDuration = 0
        presses.allowedTouchTypes = []
        presses.cancelsTouchesInView = false
        presses.delegate = self
        view.addGestureRecognizer(presses)

        let swipes = UIPanGestureRecognizer(target: self, action: #selector(remoteTouched))
        swipes.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
        swipes.cancelsTouchesInView = false
        swipes.delegate = self
        view.addGestureRecognizer(swipes)
    }

    func updateSegmentStrip(segments: [SponsorSegment], duration: TimeInterval) {
        segmentStrip.update(segments: segments, duration: duration)
        attachSegmentStrip()
    }

    func attachSegmentStrip() {
        guard let root = playerView else { return }
        segmentStrip.attach(toTransportBarIn: root)
        // Same moments suit the LIVE tags, which AVKit also builds lazily.
        liveBadgeTint.apply(in: root.window ?? root)
    }

    @objc private func remoteTouched(_ recognizer: UIGestureRecognizer) {
        guard recognizer.state == .began else { return }
        // After this event is handled, by which time AVKit has brought up (or built) the bar.
        Task { @MainActor [weak self] in self?.attachSegmentStrip() }
    }
}
#endif
