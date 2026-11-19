#if os(tvOS)
import SmartTubeIOSCore
import SwiftUI

// MARK: - TVTwitchAdNotice

/// The note over the video while a Twitch ad break is kept off the screen.
struct TVTwitchAdNotice: View {
    let adBreak: TwitchAdBreak

    var body: some View {
        Label {
            Text(
                adBreak == .lowQuality
                    ? "Ad break — lower quality until it ends" : "Ad break — Twitch has no ad-free stream right now")
        } icon: {
            Image(systemName: AppSymbol.twitch).foregroundStyle(AppColor.platform(.twitch))
        }
        .font(.callout.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(.black.opacity(0.7), in: Capsule())
        .allowsHitTesting(false)
    }
}
#endif
