#if os(tvOS)
import SmartTubeIOSCore
import SwiftUI

// MARK: - TVDetailsPanel

/// The player's "Details" tab (swipe down): the channel, then the numbers — published,
/// views, likes, dislikes, length. Fills in as the watch page and dislike counts arrive.
struct TVDetailsPanel: View {
    let vm: PlaybackViewModel
    let fallback: Video?

    var body: some View {
        let video = vm.currentVideo ?? fallback
        let details = vm.videoDetails
        HStack(alignment: .center, spacing: 64) {
            if let video { channel(video, details: details) }
            Spacer(minLength: 0)
            HStack(alignment: .top, spacing: 48) {
                if let published = published(video, details) {
                    TVStat(symbol: AppSymbol.calendar, value: published.value, label: published.label)
                }
                if vm.isLive {
                    if let watching = vm.watchingCount {
                        TVStat(symbol: AppSymbol.views, value: watching.formatted(), label: "Watching Now")
                    }
                } else if let views = vm.viewCount ?? video?.viewCount {
                    TVStat(symbol: AppSymbol.views, value: views.formatted(), label: views == 1 ? "View" : "Views")
                }
                if let likes = vm.likeCount {
                    TVStat(symbol: AppSymbol.thumbsUp, value: likes.formatted(), label: "Likes")
                }
                if let dislikes = vm.votes?.dislikes {
                    // Estimated by Return YouTube Dislike; YouTube no longer publishes them.
                    TVStat(symbol: AppSymbol.thumbsDown, value: dislikes.formatted(), label: "Dislikes")
                }
                if !vm.isLive, let duration = vm.playerInfo?.video.duration ?? video?.duration,
                    duration > 0
                {
                    TVStat(symbol: AppSymbol.clock, value: formatDuration(duration), label: "Length")
                }
            }
        }
        .padding(.horizontal, 48)
        .padding(.vertical, 36)
        // The same frosted card as the system Info tab, so it reads over any video.
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .padding(.horizontal, 80)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.easeOut(duration: 0.25), value: details)
        .animation(.easeOut(duration: 0.25), value: vm.votes)
    }

    private func channel(_ video: Video, details: VideoDetails?) -> some View {
        HStack(spacing: 24) {
            ZStack {
                Circle().fill(Color.white.opacity(0.08))
                Image(systemName: AppSymbol.person).font(.system(size: 40)).foregroundStyle(.secondary)
                if let avatar = details?.channelAvatarURL {
                    TVRemoteImage(urls: [avatar], pointWidth: 110)
                }
            }
            .frame(width: 110, height: 110)
            .clipShape(Circle())
            VStack(alignment: .leading, spacing: 6) {
                Text(video.channelTitle.nilIfEmpty ?? vm.playerInfo?.video.channelTitle ?? "")
                    .font(.headline)
                    .lineLimit(1)
                if let subscribers = details?.subscriberCountText {
                    Text(subscribers).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .frame(maxWidth: 380, alignment: .leading)
        }
    }

    /// "Nov 15, 2026" over "9 hours ago" when the watch page is in; the card's age until then.
    private func published(_ video: Video?, _ details: VideoDetails?) -> (value: String, label: String)? {
        if let date = details?.dateText {
            // Streams read "Started streaming on Nov 3, 2026" / "Streamed live on …": the date
            // goes in the value, the rest in the caption.
            for (prefix, label) in [("Started streaming on ", "Started Streaming"), ("Streamed live on ", "Streamed")]
            where date.hasPrefix(prefix) {
                return (String(date.dropFirst(prefix.count)), label)
            }
            return (date, details?.relativeDateText ?? "Published")
        }
        if let age = video?.publishedTimeText?.nilIfEmpty { return (age, "Published") }
        return nil
    }
}

/// One number on the Details tab: symbol, value, caption.
private struct TVStat: View {
    let symbol: String
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundStyle(.secondary)
                // Symbols differ in height; a fixed row keeps the numbers on one line.
                .frame(height: 44, alignment: .bottomLeading)
            Text(value)
                .font(.headline.monospacedDigit())
                .lineLimit(1)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        // Each number keeps its natural width; the channel name gives way instead.
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}
#endif
