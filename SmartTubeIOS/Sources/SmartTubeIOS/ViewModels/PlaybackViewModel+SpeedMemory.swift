import SmartTubeIOSCore
import os

private let speedLog = DiagnosticsLogger(category: "Speed")

// MARK: - Per-channel playback speed memory
//
// Each channel remembers the speed last chosen while watching it; music (music videos,
// songs, Topic/VEVO channels) always starts at 1× and is never remembered.
//
// `settings.playbackSpeed` is this view model's private copy of the settings, and every
// rate-applying path (load, fallbacks, quality switches, resume…) already uses it — so it
// holds the *effective* speed for the current video. `defaultPlaybackSpeed` keeps the
// user's global default.

/// Where a speed the user picked in the player should be persisted.
public enum PlaybackSpeedScope: Equatable, Sendable {
    /// Music: applies to this video only.
    case sessionOnly
    /// Remember for this channel.
    case channel(String)
    /// Channel unknown: becomes the new default speed.
    case global
}

extension PlaybackViewModel {
    /// The speed currently in effect (what the speed menus should show as selected).
    public var currentPlaybackSpeed: Double { settings.playbackSpeed }

    /// `PlayerInfo` only describes the current video once its response has arrived.
    private var currentPlayerInfo: PlayerInfo? {
        guard let info = playerInfo, info.video.id == currentVideo?.id else { return nil }
        return info
    }

    var isCurrentVideoMusic: Bool { currentPlayerInfo?.isMusic ?? false }

    /// The channel whose speed applies to the current video (nil for music or unknown).
    var speedMemoryChannelId: String? {
        guard !isCurrentVideoMusic else { return nil }
        let id = currentPlayerInfo?.video.channelId ?? currentVideo?.channelId
        guard let id, !id.isEmpty else { return nil }
        return id
    }

    var effectivePlaybackSpeed: Double {
        // Live can't run faster than it's broadcast: above 1× it only hits the live edge.
        if isCurrentVideoMusic || isLive { return 1.0 }
        if let channel = speedMemoryChannelId, let speed = settings.channelPlaybackSpeeds[channel] {
            return speed
        }
        return defaultPlaybackSpeed
    }

    /// Re-evaluates the effective speed and applies it if it changed.
    func applyEffectiveSpeed() {
        let speed = effectivePlaybackSpeed
        // Keep AVPlayer's resume rate in step even when the value didn't change.
        player.defaultRate = Float(speed)
        guard abs(settings.playbackSpeed - speed) > 0.001 else { return }
        settings.playbackSpeed = speed
        setPlaybackSpeed(speed)
        speedLog.notice(
            "[speed] effective \(speed)× for \(self.currentVideo?.id ?? "nil") (music=\(self.isCurrentVideoMusic) channel=\(self.speedMemoryChannelId ?? "nil"))"
        )
    }

    /// The user picked a speed in the player. Applies it now and returns where the caller
    /// should persist it (the view model can't write `SettingsStore`).
    @discardableResult
    public func userSelectedPlaybackSpeed(_ speed: Double) -> PlaybackSpeedScope {
        settings.playbackSpeed = speed
        setPlaybackSpeed(speed)
        if isCurrentVideoMusic || isLive { return .sessionOnly }
        if let channel = speedMemoryChannelId {
            settings.channelPlaybackSpeeds[channel] = speed
            return .channel(channel)
        }
        defaultPlaybackSpeed = speed
        return .global
    }
}
