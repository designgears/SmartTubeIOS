#if os(tvOS)
import SmartTubeIOSCore
import SwiftUI

// MARK: - TVMarqueeText

/// One line of text that, while `isActive` (its card has focus) and too long to fit, scrolls
/// sideways like titles in the Apple TV app: a pause, one smooth pass, a pause, again.
/// Otherwise it's plain text truncated with an ellipsis. Respects Reduce Motion.
struct TVMarqueeText: View {
    let text: String
    let font: Font
    let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var textWidth: CGFloat = 0
    @State private var boxWidth: CGFloat = 0
    @State private var offset: CGFloat = 0

    private let gap: CGFloat = 64
    /// Points per second.
    private let speed: CGFloat = 80
    private let fade: CGFloat = 18

    private var scrolls: Bool { isActive && !reduceMotion && textWidth > boxWidth + 1 && boxWidth > 0 }

    var body: some View {
        // The resting text sets the size, so the line is as tall as any one-line label.
        Text(text)
            .font(font)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(scrolls ? 0 : 1)
            .background(TVWidthReader { boxWidth = $0 })
            .background(alignment: .leading) {
                Text(text).font(font).lineLimit(1).fixedSize().hidden()
                    .background(TVWidthReader { textWidth = $0 })
            }
            .overlay(alignment: .leading) {
                if scrolls {
                    HStack(spacing: gap) {
                        Text(text).font(font).lineLimit(1).fixedSize()
                        // The copy that follows makes the loop seamless.
                        Text(text).font(font).lineLimit(1).fixedSize().accessibilityHidden(true)
                    }
                    .offset(x: offset)
                    .frame(width: boxWidth, alignment: .leading)
                    .clipped()
                    .mask(edgeFade)
                }
            }
            .task(id: scrolls) { await scroll() }
    }

    private var edgeFade: some View {
        HStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                .frame(width: offset < 0 ? fade : 0)
            Rectangle()
            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: fade)
        }
    }

    private func scroll() async {
        offset = 0
        guard scrolls else { return }
        let distance = textWidth + gap
        let duration = Double(distance / speed)
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            withAnimation(.linear(duration: duration)) { offset = -distance }
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            // The copy now sits exactly where the original started: jump back unseen.
            var reset = Transaction()
            reset.disablesAnimations = true
            withTransaction(reset) { offset = 0 }
        }
    }
}

/// Reports the width it's laid out at.
private struct TVWidthReader: View {
    let onChange: (CGFloat) -> Void

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear { onChange(proxy.size.width) }
                .onChange(of: proxy.size.width) { _, width in onChange(width) }
        }
    }
}

// MARK: - Card caption

/// Title (scrolls when focused), channel, then "views · date" — under every video card.
struct TVVideoCaption: View {
    let video: Video
    var titleFont: Font = .callout.weight(.semibold)
    var showsChannel = true

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TVMarqueeText(text: video.deArrowTitle ?? video.title, font: titleFont, isActive: isFocused)
            if showsChannel, !video.channelTitle.isEmpty {
                Text(video.channelTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let meta = video.tvMetaLine {
                Text(meta)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }
}

extension Video {
    /// "1.2M views · 3 days ago", "LIVE · 4.1K watching", "Upcoming" — nil when nothing's known.
    var tvMetaLine: String? {
        var parts: [String] = []
        if isLive {
            parts.append("LIVE")
        } else if isUpcoming {
            parts.append("Upcoming")
        }
        if viewCount != nil { parts.append(formattedViewCount) }
        if !isLive, let date = publishedTimeText?.trimmingCharacters(in: .whitespaces), !date.isEmpty {
            // Only the age: some sources put views in the same text ("1.4B views • 5mo ago").
            parts.append(RelativeAge(date)?.text ?? date)
        } else if !isLive, let publishedAt {
            parts.append(publishedAt.formatted(.relative(presentation: .named)))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
#endif
