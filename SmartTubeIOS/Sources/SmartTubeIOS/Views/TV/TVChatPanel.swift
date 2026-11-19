#if os(tvOS)
import SmartTubeIOSCore
import SwiftUI

// MARK: - TVChatPanel

/// A Twitch or Kick stream's live chat beside the video: the newest messages at the bottom,
/// each author in their own color. Read-only, so it never takes focus.
struct TVChatPanel: View {
    let feed: LiveChatFeed

    static let width: CGFloat = 520
    /// As many as fit; older ones scroll off the top.
    static let shown = 40

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Spacer(minLength: 0)
            if feed.messages.isEmpty {
                Text(feed.isConnected ? "Waiting for messages…" : "Connecting to chat…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach(feed.messages.suffix(Self.shown)) { message in
                Text("\(Text(message.author).bold().foregroundColor(Self.color(message.color)))  \(message.text)")
                    .foregroundStyle(.white)
                    .font(.callout)
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 32)
        .frame(width: Self.width)
        .frame(maxHeight: .infinity)
        .background(.black.opacity(0.62))
        .clipped()
        .animation(.easeOut(duration: 0.2), value: feed.messages.last?.id)
        .allowsHitTesting(false)
        .accessibilityLabel("Live chat")
    }

    /// The author's "#RRGGBB", or a readable default.
    static func color(_ hex: String?) -> Color {
        guard let hex, hex.hasPrefix("#"), hex.count == 7, let value = UInt32(hex.dropFirst(), radix: 16) else {
            return Color(white: 0.8)
        }
        return Color(
            red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255)
    }
}
#endif
