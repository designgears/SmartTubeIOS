import AVFoundation
import Foundation
import SmartTubeIOSCore

#if canImport(UIKit)
import UIKit
#endif

private let playerLog = DiagnosticsLogger(category: "Player")

// MARK: - Direct playback (downloads, Twitch, Kick)

extension PlaybackViewModel {
    /// Plays `item` as it is, with none of YouTube's stream handling: a downloaded file, or a
    /// Twitch or Kick HLS stream. Wires the status, end and stall observers before the item
    /// goes in (task-80 rule), then starts playing. `resumeAt` seeks once the item is ready.
    func startDirectPlayback(_ item: AVPlayerItem, video: Video, label: String, resumeAt: TimeInterval? = nil) {
        item.audioTimePitchAlgorithm = .spectral
        // Wire up observers BEFORE replaceCurrentItem (task-80 rule).
        itemObserverTask?.cancel()
        itemObserverTask = Task { [weak self] in
            for await status in item.statusStream {
                guard let self, !Task.isCancelled else { return }
                switch status {
                case .readyToPlay:
                    playerLog.notice(
                        "[benchmark] readyToPlay — \(label) — videoId=\(video.id) title=\(video.title)")
                    if let resumeAt, resumeAt > 0 { self.seek(to: resumeAt) }
                    self.loadAudioTracks(from: item)
                    self.isLoading = false
                case .failed:
                    playerLog.error("❌ \(label) AVPlayerItem failed: \(String(describing: item.error))")
                    self.error = item.error
                case .unknown:
                    break
                @unknown default:
                    break
                }
            }
        }
        player.replaceCurrentItem(with: item)
        endObserverTask?.cancel()
        endObserverTask = Task { [weak self] in
            let notifications = NotificationCenter.default.notifications(
                named: AVPlayerItem.didPlayToEndTimeNotification,
                object: item
            )
            for await _ in notifications {
                guard let self, !Task.isCancelled else { return }
                self.handlePlaybackEnd()
            }
        }
        observeDirectStalls(of: item)
        #if canImport(UIKit)
        setupRemoteCommandCenter()
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            playerLog.error("[loadAsync] \(label): AVAudioSession setActive failed: \(error.localizedDescription)")
        }
        #endif
        player.rate = Float(effectivePlaybackSpeed)
        isPlaying = true
        // Downloads, Twitch and Kick have no related videos — clear any stale state from a
        // previous YouTube session so autoplay does not fire a YouTube video when
        // this one ends. (Bug #224: wrong video played after local file ends.)
        relatedVideos = []
        hasNext = false
        #if canImport(UIKit)
        UIApplication.shared.isIdleTimerDisabled = true
        updateNowPlayingInfo()
        #endif
    }

    /// Stall recovery for direct playback (#193): wait 2 s for AVPlayer to recover by itself,
    /// then nudge it with a near-zero seek and the rate restored; at most 3 times per item.
    private func observeDirectStalls(of item: AVPlayerItem) {
        stallObserverTask?.cancel()
        stallObserverTask = Task { @MainActor [weak self] in
            let notifications = NotificationCenter.default.notifications(
                named: AVPlayerItem.playbackStalledNotification,
                object: item
            )
            for await _ in notifications {
                guard let self, !Task.isCancelled else { return }
                self.stallCount += 1
                let seconds = Int(self.currentTime)
                playerLog.notice(
                    "[stall] AVPlayerItemPlaybackStalled at t=\(seconds)s stall#\(self.stallCount) video=\(self.currentVideo?.id ?? "unknown")"
                )
                let stallError = NSError(
                    domain: "SmartTube.PlaybackStall",
                    code: 0,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "AVPlayerItemPlaybackStalled at t=\(seconds)s (stall #\(self.stallCount))"
                    ]
                )
                playerLog.recordNonFatal(
                    stallError,
                    userInfo: [
                        "video_id": self.currentVideo?.id ?? "unknown",
                        "stall_at_time": String(seconds),
                        "stall_count": String(self.stallCount),
                        "video_duration": String(Int(self.duration)),
                        "stall_trigger": "AVPlayerItemPlaybackStalled",
                    ])
                // Stall recovery (#193): wait 2 s for AVPlayer to self-heal;
                // if still stalled, nudge the pipeline with a near-zero seek
                // + explicit rate restore. Capped at 3 attempts per item.
                let recoveryCount = self.stallCount
                if recoveryCount <= 3 {
                    Task { @MainActor [weak self] in
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        guard let self, self.isPlaying, self.player.rate == 0,
                            !self.isQualityChangePending
                        else { return }
                        let seekT = self.currentTime
                        playerLog.notice(
                            "[stall] recovery#\(recoveryCount): seeking to \(seekT)s to flush pipeline")
                        self.player.seek(
                            to: CMTime(seconds: seekT, preferredTimescale: 600),
                            toleranceBefore: .zero,
                            toleranceAfter: CMTime(seconds: 1, preferredTimescale: 600)
                        ) { [weak self] _ in
                            Task { @MainActor [weak self] in
                                guard let self, self.isPlaying else { return }
                                self.player.rate = Float(self.effectivePlaybackSpeed)
                                playerLog.notice("[stall] recovery#\(recoveryCount): rate restored")
                            }
                        }
                    }
                }
            }
        }
    }

    /// Twitch and Kick: a fresh HLS URL (Twitch's tokens expire within minutes), then direct
    /// playback. None of YouTube's extras run: no PO token, SponsorBlock, DeArrow, related
    /// videos or watch-history reporting. A past broadcast resumes where it was left.
    func loadExternal(video: Video) async {
        relatedVideos = []
        hasNext = false
        sponsorSegments = []
        let saved = video.isLive ? nil : await VideoStateStore.shared.state(for: video.id)?.position
        do {
            let url = try await ExternalStreamResolver.playbackURL(for: video)
            guard !Task.isCancelled, currentVideo?.id == video.id else { return }
            playerLog.notice("[external] \(video.platform.rawValue) \(video.isLive ? "live" : "VOD") \(video.id)")
            startDirectPlayback(
                AVPlayerItem(url: url), video: video, label: video.platform.rawValue,
                resumeAt: (saved ?? 0) > 5 ? saved : nil)
        } catch {
            guard !Task.isCancelled, currentVideo?.id == video.id else { return }
            playerLog.error("[external] \(video.id) failed: \(error.localizedDescription)")
            self.error = error
            isLoading = false
        }
    }
}
