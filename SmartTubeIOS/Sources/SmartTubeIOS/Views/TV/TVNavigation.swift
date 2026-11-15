#if os(tvOS)
import SmartTubeIOSCore
import SwiftUI

// MARK: - TVTab

/// Top-level destinations in the tvOS sidebar.
enum TVTab: Hashable {
    case home
    case subscriptions
    case search
    case explore(BrowseSection.SectionType)
    case history
    case watchLater
    case playlists
    case channels
    case queue
    case accounts
    case settings
}

// MARK: - TVRoute

/// Pushed destinations inside a sidebar tab's NavigationStack.
enum TVRoute: Hashable {
    case channel(id: String, title: String)
    case playlist(id: String, title: String)
}

// MARK: - TVPlayRequest

struct TVPlayRequest: Identifiable {
    let id = UUID()
    let video: Video
}

// MARK: - TVNavigator

/// Owns tvOS navigation state: sidebar selection, one NavigationPath per tab, and the
/// full-screen player. Injected into the environment by `TVRootView`.
@MainActor @Observable
final class TVNavigator {
    var selection: TVTab = .home
    var nowPlaying: TVPlayRequest?
    private var paths: [TVTab: NavigationPath] = [:]

    func path(for tab: TVTab) -> Binding<NavigationPath> {
        Binding(
            get: { self.paths[tab] ?? NavigationPath() },
            set: { self.paths[tab] = $0 }
        )
    }

    /// Opens a video. Playlist placeholders (id == playlistId) open the playlist instead.
    /// When `queue` is given, it becomes the Current Queue so Next follows it.
    func play(_ video: Video, queue: [Video]? = nil) {
        if let playlistId = video.playlistId, playlistId == video.id {
            open(.playlist(id: playlistId, title: video.title))
            return
        }
        if let queue, !queue.isEmpty {
            Task {
                await CurrentQueueStore.shared.replaceAll(with: queue)
                self.nowPlaying = TVPlayRequest(video: video)
            }
        } else {
            nowPlaying = TVPlayRequest(video: video)
        }
    }

    /// Pushes a route onto the current tab (closing the player first if it is open).
    func open(_ route: TVRoute) {
        nowPlaying = nil
        paths[selection, default: NavigationPath()].append(route)
    }

    func openChannel(of video: Video) {
        guard let channelId = video.channelId, !channelId.isEmpty else { return }
        open(.channel(id: channelId, title: video.channelTitle))
    }
}

// MARK: - TVTabStack

/// A tab's NavigationStack wired to the navigator's path and the shared route destinations.
///
/// `routable: false` gives a plain stack. Use it for screens that push with SwiftUI's own
/// view-based links (Settings: Picker option lists, NavigationLink sub-pages): a
/// path-bound stack doesn't track those pushes, so the pushed page renders blank and
/// Menu then exits the app instead of popping.
struct TVTabStack<Content: View>: View {
    let tab: TVTab
    var routable = true
    @ViewBuilder var content: () -> Content
    @Environment(TVNavigator.self) private var navigator

    var body: some View {
        if routable {
            NavigationStack(path: navigator.path(for: tab)) {
                content()
                    .navigationDestination(for: TVRoute.self) { route in
                        switch route {
                        case .channel(let id, let title):
                            TVChannelView(channelId: id, title: title)
                        case .playlist(let id, let title):
                            TVPlaylistView(playlistId: id, title: title)
                        }
                    }
            }
        } else {
            NavigationStack { content() }
        }
    }
}
#endif
