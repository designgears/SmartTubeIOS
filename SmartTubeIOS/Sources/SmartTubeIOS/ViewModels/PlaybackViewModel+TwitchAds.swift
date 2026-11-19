import AVFoundation
import Foundation
import SmartTubeIOSCore

private let playerLog = DiagnosticsLogger(category: "Player")

// MARK: - TwitchAdBreak

/// What the player shows during a Twitch ad break it keeps off the screen.
public enum TwitchAdBreak: Equatable, Sendable {
    /// Playing Twitch's ad-free copy of the stream (360p at most) until the break ends.
    case lowQuality
    /// No ad-free copy was found: the break plays (it ends on its own).
    case unavoidable
}

// MARK: - TwitchPlaylistLoader

/// Serves a master playlist the app already fetched, under its own scheme, so AVPlayer plays
/// exactly that usher session (its variant URLs are absolute and load directly). The ad watcher
/// polls a variant of the same session: Twitch decides ads per session.
final class TwitchPlaylistLoader: NSObject, AVAssetResourceLoaderDelegate, @unchecked Sendable {
    static let scheme = "smarttube-twitch"
    private let data: Data

    init(playlist: String) {
        data = Data(playlist.utf8)
    }

    /// The URL to give AVPlayer for this playlist.
    static let url = URL(string: "\(scheme)://master.m3u8")!  // swiftlint:disable:this force_unwrapping

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        guard loadingRequest.request.url?.scheme == Self.scheme else { return false }
        if let info = loadingRequest.contentInformationRequest {
            // A UTI, not a MIME type (see YTHLSProxyLoader).
            info.contentType = "public.m3u-playlist"
            info.contentLength = Int64(data.count)
            info.isByteRangeAccessSupported = false
        }
        loadingRequest.dataRequest?.respond(with: data)
        loadingRequest.finishLoading()
        return true
    }
}

// MARK: - Twitch live, ads blocked

extension PlaybackViewModel {
    /// Twitch live with ad blocking on (Settings › Twitch & Kick, `TwitchAds`): the `popout`
    /// stream, which has no pre-roll; if it starts in a break anyway, Twitch's ad-free 360p copy
    /// instead. Then the main stream is watched: a break switches to the ad-free copy, its end
    /// switches back to full quality.
    func playTwitchLive(video: Video, target: ExternalID.Parsed) async throws {
        let main = try await TwitchClient.shared.playbackPlaylist(for: target, playerType: TwitchAds.playerType)
        guard !Task.isCancelled, currentVideo?.id == video.id else { return }
        let watched = TwitchAds.watchedVariant(in: main.text)
        var onBackup = false
        if let watched, let playlist = await TwitchAds.fetch(watched), TwitchAds.hasAds(playlist) {
            if let backup = await adFreeBackup(target) {
                playerLog.notice("[twitchAds] pre-roll on \(target.key): starting on the ad-free copy")
                playTwitchPlaylist(backup, video: video, label: "twitch-adfree")
                onBackup = true
                twitchAdBreak = .lowQuality
            } else {
                twitchAdBreak = .unavoidable
            }
        }
        if !onBackup { playTwitchPlaylist(main.text, video: video, label: "twitch") }
        guard let watched else { return }
        watchTwitchAds(video: video, target: target, watched: watched, onBackup: onBackup)
    }

    func endTwitchAdWatch() {
        twitchAdTask?.cancel()
        twitchAdTask = nil
        twitchAdBreak = nil
    }

    /// load(): clears the item, and stops watching the previous Twitch stream.
    func clearItemAndAdWatch() {
        player.replaceCurrentItem(with: nil)
        endTwitchAdWatch()
    }

    /// stop(): pauses, and stops watching for Twitch ad breaks.
    func pauseEndingAdWatch() {
        player.pause()
        endTwitchAdWatch()
    }

    private func playTwitchPlaylist(_ playlist: String, video: Video, label: String) {
        let loader = TwitchPlaylistLoader(playlist: playlist)
        let asset = AVURLAsset(url: TwitchPlaylistLoader.url)
        // AVFoundation's API takes a queue for the loader's callbacks.
        asset.resourceLoader.setDelegate(loader, queue: DispatchQueue.global(qos: .userInitiated))
        twitchPlaylistLoader = loader
        startDirectPlayback(AVPlayerItem(asset: asset), video: video, label: label)
    }

    /// The first backup player type whose stream has no ads right now.
    private func adFreeBackup(_ target: ExternalID.Parsed) async -> String? {
        for playerType in TwitchAds.backupPlayerTypes {
            guard let backup = try? await TwitchClient.shared.playbackPlaylist(for: target, playerType: playerType),
                let variant = TwitchAds.watchedVariant(in: backup.text),
                let playlist = await TwitchAds.fetch(variant), !TwitchAds.hasAds(playlist)
            else { continue }
            return backup.text
        }
        return nil
    }

    /// Polls the main stream's session every `TwitchAds.pollInterval`, also while the backup
    /// plays, so the break's end is seen.
    private func watchTwitchAds(
        video: Video, target: ExternalID.Parsed, watched initial: URL, onBackup initialBackup: Bool
    ) {
        twitchAdTask?.cancel()
        twitchAdTask = Task { [weak self] in
            var watched = initial
            var onBackup = initialBackup
            while !Task.isCancelled {
                try? await Task.sleep(for: TwitchAds.pollInterval)
                guard let self, !Task.isCancelled, self.currentVideo?.id == video.id else { return }
                guard let playlist = await TwitchAds.fetch(watched) else { continue }
                let hasAds = TwitchAds.hasAds(playlist)
                if onBackup, !hasAds {
                    // Break over: full quality again, from a fresh session.
                    guard
                        let main = try? await TwitchClient.shared.playbackPlaylist(
                            for: target, playerType: TwitchAds.playerType),
                        let fresh = TwitchAds.watchedVariant(in: main.text), !Task.isCancelled
                    else { continue }
                    playerLog.notice("[twitchAds] break over on \(target.key): back to full quality")
                    self.playTwitchPlaylist(main.text, video: video, label: "twitch")
                    (watched, onBackup) = (fresh, false)
                    self.twitchAdBreak = nil
                } else if !onBackup, hasAds {
                    if let backup = await self.adFreeBackup(target), !Task.isCancelled {
                        playerLog.notice("[twitchAds] break on \(target.key): ad-free copy until it ends")
                        self.playTwitchPlaylist(backup, video: video, label: "twitch-adfree")
                        onBackup = true
                        self.twitchAdBreak = .lowQuality
                    } else {
                        self.twitchAdBreak = .unavoidable
                    }
                } else if !onBackup, !hasAds, self.twitchAdBreak != nil {
                    self.twitchAdBreak = nil
                }
            }
        }
    }
}
