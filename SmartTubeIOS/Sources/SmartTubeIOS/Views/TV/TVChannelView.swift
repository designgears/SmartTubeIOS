#if os(tvOS)
import SmartTubeIOSCore
import SwiftUI

// MARK: - TVChannelView

struct TVChannelView: View {
    let channelId: String
    let title: String

    @Environment(\.innerTubeAPI) private var api
    @Environment(AuthService.self) private var auth
    @Environment(TVNavigator.self) private var navigator
    @Environment(SettingsStore.self) private var store
    @State private var vm: ChannelViewModel?
    @State private var isFollowing = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TVLayout.sectionSpacing) {
                header
                if let vm {
                    // Streaming now comes first, as on YouTube.
                    if !vm.live.isEmpty {
                        TVShelf(title: "Live", items: vm.live, prefetchWidth: TVLayout.cardWidth) { video in
                            TVVideoCard(video: video) { navigator.play(video) }
                        }
                    }
                    // Settings › Hide Shorts covers channel pages too.
                    let shorts = store.settings.hideShorts ? [] : vm.shorts.uniquedByID()
                    if !shorts.isEmpty {
                        TVShelf(
                            title: "Shorts", items: shorts, onReachEnd: { vm.loadMoreShorts() },
                            pageKey: vm.shorts.count,
                            card: { video in TVShortCard(video: video) { navigator.play(video) } }
                        )
                    }
                    if !vm.videos.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Videos")
                                .font(.title3.weight(.bold))
                                .padding(.leading, TVLayout.pageInset)
                            TVVideoGrid(
                                videos: vm.videos.filter { !$0.isShort }.uniquedByID(),
                                onReachEnd: { vm.loadMore() },
                                pageKey: vm.videos.count,
                                onSelect: { navigator.play($0) }
                            )
                        }
                    } else if vm.isLoading {
                        TVLoadingView().frame(height: 500)
                    } else if let error = vm.error {
                        TVMessageView(
                            systemImage: AppSymbol.warningOutline,
                            title: "Couldn't load this channel",
                            message: error.localizedDescription,
                            actionTitle: "Try Again"
                        ) { vm.load(channelId: channelId) }
                        .frame(height: 500)
                    } else if shorts.isEmpty, vm.live.isEmpty {
                        TVMessageView(
                            systemImage: AppSymbol.playRectangle,
                            title: "No videos",
                            message: "This channel hasn't posted any videos yet.",
                            actionTitle: "Go Back"
                        ) { dismiss() }
                        .frame(height: 500)
                    }
                }
            }
            .padding(.bottom, 80)
        }
        .task {
            guard vm == nil else { return }
            let model = ChannelViewModel(api: api)
            vm = model
            model.load(channelId: channelId)
            isFollowing = await LocalSubscriptionStore.shared.isFollowing(channelId)
        }
    }

    private var header: some View {
        let channel = vm?.channel
        return HStack(alignment: .center, spacing: 48) {
            AsyncImage(url: channel?.thumbnailURL) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    ZStack {
                        Color.white.opacity(0.08)
                        Image(systemName: AppSymbol.person).font(.system(size: 80)).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 220, height: 220)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 14) {
                Text(channel?.title ?? title)
                    .font(.system(size: 56, weight: .bold))
                    .lineLimit(1)
                if let subs = channel?.subscriberCount, !subs.isEmpty {
                    Text(subs).font(.headline).foregroundStyle(.secondary)
                }
                if let description = channel?.description, !description.isEmpty {
                    Text(description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: 1100, alignment: .leading)
                }
                if !auth.isSignedIn {
                    Button {
                        toggleFollow()
                    } label: {
                        Label(
                            isFollowing ? "Following" : "Follow",
                            systemImage: isFollowing ? "checkmark" : "plus")
                    }
                    .padding(.top, 8)
                }
            }
            Spacer()
        }
        .padding(.horizontal, TVLayout.pageInset)
        .padding(.top, 40)
        .focusSection()
    }

    private func toggleFollow() {
        let newValue = !isFollowing
        isFollowing = newValue
        let local = LocalChannel(
            id: channelId, title: vm?.channel?.title ?? title, thumbnailURL: vm?.channel?.thumbnailURL)
        Task {
            if newValue {
                await LocalSubscriptionStore.shared.follow(local)
            } else {
                await LocalSubscriptionStore.shared.unfollow(channelId: channelId)
            }
        }
    }
}

// MARK: - TVPlaylistView

/// A playlist (or the Current Queue). Playing from here keeps Next within the playlist.
struct TVPlaylistView: View {
    let playlistId: String
    let title: String

    @Environment(\.innerTubeAPI) private var api
    @Environment(TVNavigator.self) private var navigator
    @State private var vm: PlaylistViewModel?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                if let vm {
                    if !vm.videos.isEmpty {
                        TVVideoGrid(
                            videos: vm.videos.uniquedByID(),
                            onReachEnd: {
                                if let last = vm.videos.last { vm.loadMoreIfNeeded(lastVideo: last) }
                            },
                            onSelect: { video in navigator.play(video, queue: vm.videos) }
                        )
                    } else if vm.isLoading {
                        TVLoadingView().frame(height: 600)
                    } else if let error = vm.error {
                        TVMessageView(
                            systemImage: AppSymbol.warningOutline,
                            title: "Couldn't load this playlist",
                            message: error.localizedDescription,
                            actionTitle: "Try Again"
                        ) { vm.load(playlistId: playlistId, refresh: true) }
                        .frame(height: 600)
                    } else {
                        TVMessageView(
                            systemImage: isQueue ? AppSymbol.upNext : AppSymbol.playlist,
                            title: isQueue ? "Your queue is empty" : "This playlist is empty",
                            message: isQueue ? "Play a playlist to fill the queue." : nil,
                            actionTitle: "Browse Home", action: { navigator.selection = .home }
                        )
                        .frame(height: 600)
                    }
                }
            }
            .padding(.bottom, 80)
        }
        .task {
            if vm == nil {
                let model = PlaylistViewModel(api: api)
                vm = model
                model.load(playlistId: playlistId)
            } else if isQueue {
                vm?.load(playlistId: playlistId, refresh: true)
            }
        }
    }

    private var isQueue: Bool { playlistId == CurrentQueueStore.playlistID }

    private var header: some View {
        VStack(alignment: .leading, spacing: 20) {
            TVPageHeader(
                title: title,
                subtitle: (vm?.videos.isEmpty == false) ? "\(vm?.videos.count ?? 0) videos" : nil
            )
            if let videos = vm?.videos, let first = videos.first {
                HStack(spacing: 28) {
                    Button {
                        navigator.play(first, queue: videos)
                    } label: {
                        Label("Play All", systemImage: AppSymbol.play)
                    }
                    Button {
                        let shuffled = videos.shuffled()
                        if let start = shuffled.first { navigator.play(start, queue: shuffled) }
                    } label: {
                        Label("Shuffle", systemImage: AppSymbol.shuffle)
                    }
                }
                .padding(.horizontal, TVLayout.pageInset)
                .focusSection()
            }
        }
    }
}
#endif
