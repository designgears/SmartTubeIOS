#if os(tvOS)
import SmartTubeIOSCore
import SwiftUI

// MARK: - Layout

/// Shared metrics for the tvOS UI (points on a 1920×1080 canvas).
enum TVLayout {
    static let pageInset: CGFloat = 80
    static let shelfSpacing: CGFloat = 48
    static let sectionSpacing: CGFloat = 56
    static let cardWidth: CGFloat = 400
    static let shortWidth: CGFloat = 230
    static let channelSize: CGFloat = 190
    static let cornerRadius: CGFloat = 14
    /// Full-page grids: 4 fixed columns sized to fit inside the tvOS safe area.
    static let gridCardWidth: CGFloat = 360
    static let gridColumns = Array(
        repeating: GridItem(.fixed(gridCardWidth), spacing: 40, alignment: .top), count: 4)
}

extension Array where Element == Video {
    /// Removes duplicate ids (feeds occasionally repeat items), keeping first occurrence.
    func uniquedByID() -> [Video] {
        var seen = Set<String>()
        return filter { seen.insert($0.id).inserted }
    }
}

// MARK: - Thumbnail

struct TVVideoThumbnail: View {
    let video: Video
    var showsBadges = true
    /// Watched fraction to draw as the red bar. Defaults to YouTube's own resume progress.
    var progress: Double?
    /// On-screen width, so the thumbnail is downsampled to the size actually shown.
    var pointWidth: CGFloat = TVLayout.cardWidth

    /// Thumbnail candidates, best first. Shared with prefetching so cache keys match.
    static func urls(for video: Video) -> [URL] {
        video.highResThumbnailFallbackURLs + [video.thumbnailURL].compactMap { $0 }
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            TVRemoteImage(urls: Self.urls(for: video), pointWidth: pointWidth)

            if showsBadges {
                if let progress = progress ?? video.watchProgress, progress > 0.02 {
                    GeometryReader { geo in
                        VStack {
                            Spacer()
                            ZStack(alignment: .leading) {
                                Rectangle().fill(.white.opacity(0.35))
                                Rectangle().fill(.red).frame(width: geo.size.width * min(progress, 1))
                            }
                            .frame(height: 6)
                        }
                    }
                }
                HStack {
                    if video.isLive {
                        TVBadge(text: "LIVE", background: .red)
                    } else if video.isUpcoming {
                        TVBadge(text: "UPCOMING", background: .black.opacity(0.75))
                    }
                    Spacer()
                    if !video.isLive, video.duration != nil {
                        TVBadge(text: video.formattedDuration, background: .black.opacity(0.75))
                    }
                }
                .padding(12)
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
    }
}

struct TVBadge: View {
    let text: String
    let background: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(background, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

// MARK: - Video card

struct TVVideoCard: View {
    let video: Video
    var width: CGFloat = TVLayout.cardWidth
    /// Extra long-press action that takes the card off its shelf (e.g. Continue Watching).
    var removal: TVCardRemoval?
    let action: () -> Void

    @Environment(TVNavigator.self) private var navigator
    @Environment(AuthService.self) private var auth
    @Environment(\.innerTubeAPI) private var api
    /// Locally saved watch position (fraction), from the player's checkpoints.
    @State private var localProgress: Double?

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 18) {
                TVVideoThumbnail(video: video, progress: localProgress, pointWidth: width)
                    .frame(width: width, height: width * 9 / 16)
                    .clipShape(RoundedRectangle(cornerRadius: TVLayout.cornerRadius, style: .continuous))
                    .hoverEffect(.highlight)
                VStack(alignment: .leading, spacing: 6) {
                    Text(video.deArrowTitle ?? video.title)
                        .font(.callout.weight(.semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(width: width, height: 96, alignment: .topLeading)
            }
        }
        .buttonStyle(.borderless)
        .contextMenu { TVVideoContextMenu(video: video, removal: removal) }
        // Re-read when the player closes so the bar reflects what was just watched.
        .task(id: TVProgressKey(videoId: video.id, playerOpen: navigator.nowPlaying != nil)) {
            guard navigator.nowPlaying == nil else { return }
            localProgress = await VideoStateStore.shared.state(for: video.id)?.watchedFraction
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if !video.channelTitle.isEmpty { parts.append(video.channelTitle) }
        if video.viewCount != nil { parts.append(video.formattedViewCount) }
        if let published = video.publishedTimeText, !published.isEmpty { parts.append(published) }
        return parts.joined(separator: " · ")
    }
}

/// A card's "remove from this shelf" menu action.
struct TVCardRemoval {
    let title: String
    let action: () -> Void
}

struct TVVideoContextMenu: View {
    let video: Video
    var removal: TVCardRemoval?
    @Environment(TVNavigator.self) private var navigator
    @Environment(AuthService.self) private var auth
    @Environment(\.innerTubeAPI) private var api

    var body: some View {
        Button("Play", systemImage: AppSymbol.play) { navigator.play(video) }
        if let channelId = video.channelId, !channelId.isEmpty {
            Button("Go to Channel", systemImage: AppSymbol.personSquare) { navigator.openChannel(of: video) }
        }
        if auth.isSignedIn {
            Button("Save to Watch Later", systemImage: AppSymbol.clock) {
                Task { _ = try? await api.addToWatchLater(videoId: video.id) }
            }
        }
        if let removal {
            Button(removal.title, systemImage: AppSymbol.xmarkCircle, role: .destructive, action: removal.action)
        }
    }
}

// MARK: - Shorts card

struct TVShortCard: View {
    let video: Video
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                TVRemoteImage(
                    urls: [video.portraitThumbnailURL, video.thumbnailURL].compactMap { $0 },
                    pointWidth: TVLayout.shortWidth
                )
                .frame(width: TVLayout.shortWidth, height: TVLayout.shortWidth * 16 / 9)
                .clipShape(RoundedRectangle(cornerRadius: TVLayout.cornerRadius, style: .continuous))
                .hoverEffect(.highlight)
                Text(video.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
                    .frame(width: TVLayout.shortWidth, height: 64, alignment: .topLeading)
            }
        }
        .buttonStyle(.borderless)
        .contextMenu { TVVideoContextMenu(video: video) }
    }
}

// MARK: - Channel card

struct TVChannelCard: View {
    let title: String
    let thumbnailURL: URL?
    var subtitle: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 18) {
                ZStack {
                    Image(systemName: AppSymbol.person).font(.system(size: 64)).foregroundStyle(.secondary)
                    if let thumbnailURL {
                        TVRemoteImage(urls: [thumbnailURL], pointWidth: TVLayout.channelSize)
                    }
                }
                .background(Color.white.opacity(0.08))
                .frame(width: TVLayout.channelSize, height: TVLayout.channelSize)
                .clipShape(Circle())
                .modifier(TVAvatarFocus())
                VStack(spacing: 4) {
                    Text(title).font(.callout.weight(.semibold)).lineLimit(1)
                    if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                }
                .frame(width: TVLayout.channelSize + 60)
            }
        }
        .buttonStyle(TVPlainFocusButtonStyle())
    }
}

// MARK: - Shelf

/// A titled horizontal row of cards. Calls `onReachEnd` when the last item appears.
struct TVShelf<Item: Identifiable, Card: View>: View {
    let title: String
    let items: [Item]
    var onReachEnd: (() -> Void)?
    /// Card width for warming the next thumbnails as the row scrolls (video rows only).
    var prefetchWidth: CGFloat?
    @ViewBuilder let card: (Item) -> Card

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title3.weight(.bold))
                .padding(.leading, TVLayout.pageInset)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: TVLayout.shelfSpacing) {
                    ForEach(items) { item in
                        card(item)
                            .onAppear {
                                if item.id == items.last?.id { onReachEnd?() }
                                if let prefetchWidth, let videos = items as? [Video],
                                    let index = items.firstIndex(where: { $0.id == item.id })
                                {
                                    TVImagePipeline.prefetchThumbnails(videos, after: index, pointWidth: prefetchWidth)
                                }
                            }
                    }
                }
                .padding(.horizontal, TVLayout.pageInset)
                .padding(.vertical, 24)
            }
            .scrollClipDisabled()
        }
        .focusSection()
    }
}

// MARK: - Grid

/// Paging grid of video cards for full-page feeds.
struct TVVideoGrid: View {
    let videos: [Video]
    var onReachEnd: (() -> Void)?
    let onSelect: (Video) -> Void

    var body: some View {
        LazyVGrid(columns: TVLayout.gridColumns, alignment: .leading, spacing: 56) {
            ForEach(videos) { video in
                TVVideoCard(video: video, width: TVLayout.gridCardWidth) { onSelect(video) }
                    .onAppear {
                        if video.id == videos.last?.id { onReachEnd?() }
                        if let index = videos.firstIndex(where: { $0.id == video.id }) {
                            TVImagePipeline.prefetchThumbnails(videos, after: index, pointWidth: TVLayout.gridCardWidth)
                        }
                    }
            }
        }
        .padding(.horizontal, TVLayout.pageInset)
        .padding(.vertical, 24)
        .focusSection()
    }
}

// MARK: - Page header

struct TVPageHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.largeTitle.weight(.bold))
            if let subtitle { Text(subtitle).font(.headline).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, TVLayout.pageInset)
        .padding(.top, 24)
    }
}

// MARK: - Full-page states

struct TVMessageView: View {
    let systemImage: String
    let title: String
    var message: String?
    var actionTitle: String?
    var action: (() -> Void)?
    var secondaryTitle: String?
    var secondaryAction: (() -> Void)?

    var body: some View {
        VStack(spacing: 28) {
            Image(systemName: systemImage)
                .font(.system(size: 110, weight: .light))
                .foregroundStyle(.secondary)
            Text(title).font(.title2.weight(.bold)).multilineTextAlignment(.center)
            if let message {
                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 900)
            }
            let hasButtons = (actionTitle != nil && action != nil) || (secondaryTitle != nil && secondaryAction != nil)
            if hasButtons {
                HStack(spacing: 32) {
                    if let actionTitle, let action { Button(actionTitle, action: action) }
                    if let secondaryTitle, let secondaryAction { Button(secondaryTitle, action: secondaryAction) }
                }
                .padding(.top, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(80)
        // A page with nothing focusable traps the focus engine (can't return to the
        // sidebar), so a button-less message is itself focusable.
        .modifier(TVFocusableIf(enabled: !hasAnyButton))
        .focusSection()
    }

    private var hasAnyButton: Bool {
        (actionTitle != nil && action != nil) || (secondaryTitle != nil && secondaryAction != nil)
    }
}

/// Makes a container focusable only when it has no focusable children.
struct TVFocusableIf: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled { content.focusable() } else { content }
    }
}

struct TVLoadingView: View {
    var message: String?

    var body: some View {
        VStack(spacing: 24) {
            ProgressView().scaleEffect(1.6)
            if let message { Text(message).font(.headline).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Keeps focus on the page while loading so it can never get stuck.
        .focusable()
    }
}

/// Prompt shown on pages that need a YouTube account.
struct TVSignInPrompt: View {
    let title: String
    let message: String
    @State private var showSignIn = false

    var body: some View {
        TVMessageView(
            systemImage: AppSymbol.personCircleQuestion,
            title: title,
            message: message,
            actionTitle: "Sign In"
        ) { showSignIn = true }
        .fullScreenCover(isPresented: $showSignIn) { SignInView() }
    }
}
#endif

#if os(tvOS)
/// Task identity for re-reading local watch progress: changes per video and whenever the
/// full-screen player opens or closes.
struct TVProgressKey: Hashable {
    let videoId: String
    let playerOpen: Bool
}
#endif

#if os(tvOS)
/// Button style with no system focus platter; the label draws its own focus state
/// (see `TVAvatarFocus`). Used for circular avatars, where the stock lift is a square.
struct TVPlainFocusButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

/// Focus treatment for a circular avatar: scale up, white ring, soft shadow.
struct TVAvatarFocus: ViewModifier {
    @Environment(\.isFocused) private var isFocused

    func body(content: Content) -> some View {
        content
            .overlay(Circle().strokeBorder(.white, lineWidth: isFocused ? 6 : 0))
            .scaleEffect(isFocused ? 1.12 : 1)
            .shadow(color: .black.opacity(isFocused ? 0.5 : 0), radius: 24, y: 12)
            .animation(.easeOut(duration: 0.18), value: isFocused)
    }
}
#endif

#if os(tvOS)
/// Placeholder row with the real shelf's dimensions, shown while a shelf loads.
struct TVShelfSkeleton: View {
    let title: String
    var count = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title3.weight(.bold))
                .padding(.leading, TVLayout.pageInset)
            HStack(alignment: .top, spacing: TVLayout.shelfSpacing) {
                ForEach(0..<count, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 18) {
                        RoundedRectangle(cornerRadius: TVLayout.cornerRadius, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                            .frame(width: TVLayout.cardWidth, height: TVLayout.cardWidth * 9 / 16)
                        RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.06))
                            .frame(width: TVLayout.cardWidth * 0.8, height: 22)
                        RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.04))
                            .frame(width: TVLayout.cardWidth * 0.5, height: 18)
                    }
                    .frame(height: TVLayout.cardWidth * 9 / 16 + 18 + 96, alignment: .top)
                }
            }
            .padding(.horizontal, TVLayout.pageInset)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
        }
        .accessibilityHidden(true)
    }
}
#endif
