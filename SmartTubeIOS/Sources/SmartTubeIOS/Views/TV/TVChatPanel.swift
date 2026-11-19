#if os(tvOS)
import SmartTubeIOSCore
import SwiftUI

// MARK: - TVChatPanel

/// A Twitch or Kick stream's live chat beside the video: the newest messages at the bottom,
/// each author in their own color. Read-only, so it never takes focus.
struct TVChatPanel: View {
    let feed: LiveChatFeed

    static let width: CGFloat = 520
    /// More than fit; older ones go off the top.
    static let shown = 30

    var body: some View {
        // The screen's exact height: a flexible frame would grow with the messages instead of
        // clipping them, and the overflow would be centered.
        GeometryReader { geometry in
            messages
                .frame(width: Self.width, height: geometry.size.height, alignment: .bottom)
                .background(.black.opacity(0.62))
                .clipped()
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .animation(.easeOut(duration: 0.2), value: feed.messages.last?.id)
        .allowsHitTesting(false)
        .accessibilityLabel("Live chat")
    }

    /// Newest at the bottom, above the TV's overscan; older ones go off the top.
    private var messages: some View {
        VStack(alignment: .leading, spacing: 10) {
            if feed.messages.isEmpty {
                Text(feed.isConnected ? "Waiting for messages…" : "Connecting to chat…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach(feed.messages.suffix(Self.shown)) { message in
                Text("\(Text(message.author).bold().foregroundColor(Self.color(message.color)))  \(message.text)")
                    .foregroundStyle(.white)
                    .font(.callout)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 70)
        .frame(width: Self.width)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// The author's "#RRGGBB", or a readable default.
    static func color(_ hex: String?) -> Color {
        guard let hex, hex.hasPrefix("#"), hex.count == 7, let value = UInt32(hex.dropFirst(), radix: 16) else {
            return Color(white: 0.8)
        }
        var (red, green, blue) = (
            Double((value >> 16) & 0xFF) / 255, Double((value >> 8) & 0xFF) / 255, Double(value & 0xFF) / 255
        )
        // Dark names (navy, dark green) vanish on the dark panel: lift them toward white.
        let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        if luminance < minimumLuminance {
            let lift = (minimumLuminance - luminance) / (1 - luminance)
            (red, green, blue) = (red + (1 - red) * lift, green + (1 - green) * lift, blue + (1 - blue) * lift)
        }
        return Color(red: red, green: green, blue: blue)
    }

    static let minimumLuminance = 0.45
}
#endif
