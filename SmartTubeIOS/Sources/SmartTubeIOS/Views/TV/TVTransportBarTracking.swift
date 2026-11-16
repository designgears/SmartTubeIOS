#if os(tvOS)
import AVKit
import SwiftUI
import UIKit

// MARK: - Transport-bar visibility

// Whether the transport bar is up, for the SponsorBlock strip drawn over it.
// `willTransitionToVisibilityOfTransportBar` always reports the bar hiding, but not the
// bar appearing for left/right skips and scrubbing. So those also count as "bar showing";
// the delegate's hide event ends it, with a safety timeout in case the bar never actually
// appeared. The timeout only runs once the remote is let go — scrubbing (holding
// left/right, or swiping the touch surface) keeps the bar up for as long as it lasts —
// and never while paused, when the bar stays up.
// (Select/Play-Pause are left to the delegate: resuming doesn't always show the bar.)
extension TVNativePlayer.Coordinator {
    func installInteractionRecognizers(on view: UIView) {
        // Down shows the strip and holds it; release starts the countdown.
        let presses = UILongPressGestureRecognizer(target: self, action: #selector(pressChanged))
        presses.minimumPressDuration = 0
        let pressTypes: [UIPress.PressType] = [.leftArrow, .rightArrow]
        presses.allowedPressTypes = pressTypes.map { NSNumber(value: $0.rawValue) }
        presses.allowedTouchTypes = []
        presses.cancelsTouchesInView = false
        presses.delegate = self
        view.addGestureRecognizer(presses)

        let swipes = UIPanGestureRecognizer(target: self, action: #selector(touchSurfaceChanged))
        swipes.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
        swipes.cancelsTouchesInView = false
        swipes.delegate = self
        view.addGestureRecognizer(swipes)
    }

    @objc private func pressChanged(_ recognizer: UIGestureRecognizer) {
        remoteInteraction(recognizer.state)
    }

    @objc private func touchSurfaceChanged(_ recognizer: UIGestureRecognizer) {
        // A swipe scrubs only while the bar is up; it doesn't bring the bar up.
        guard transportBar?.isVisible == true else { return }
        remoteInteraction(recognizer.state)
    }

    private func remoteInteraction(_ state: UIGestureRecognizer.State) {
        switch state {
        case .began, .changed:
            setTransportBarVisible(true)
            transportBarSafetyHide?.cancel()
        case .ended, .cancelled, .failed:
            scheduleSafetyHide()
        default:
            break
        }
    }

    private func scheduleSafetyHide() {
        transportBarSafetyHide?.cancel()
        transportBarSafetyHide = Task { [weak self] in
            try? await Task.sleep(for: Self.transportBarSafetyTimeout)
            guard !Task.isCancelled, let self else { return }
            // Paused (e.g. mid-scrub) the bar stays up: look again later.
            if self.vm?.player.timeControlStatus == .paused {
                self.scheduleSafetyHide()
            } else {
                self.setTransportBarVisible(false)
            }
        }
    }
}
#endif
