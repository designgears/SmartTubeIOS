import Foundation
import Observation

// MARK: - ExternalFollowStore

/// Twitch and Kick channels followed in SmartTube, kept on the device. Kick has no sign-in a
/// TV can use, so these are its follows; for Twitch they are the follows until an account is
/// signed in (then the account's follows are added).
@MainActor
@Observable
public final class ExternalFollowStore {
    public static let shared = ExternalFollowStore()

    static let defaultsKey = "st_external_follows"

    /// Newest first.
    public private(set) var all: [Channel] = []
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.defaultsKey),
            let saved = try? JSONDecoder().decode([Channel].self, from: data)
        {
            all = saved
        }
    }

    public func channels(_ platform: StreamPlatform) -> [Channel] {
        all.filter { $0.platform == platform }
    }

    public func isFollowing(_ channelId: String) -> Bool {
        all.contains { $0.id == channelId }
    }

    public func follow(_ channel: Channel) {
        guard channel.platform != .youtube else { return }
        all.removeAll { $0.id == channel.id }
        all.insert(channel, at: 0)
        save()
    }

    public func unfollow(_ channelId: String) {
        all.removeAll { $0.id == channelId }
        save()
    }

    /// Refreshes a followed channel's name and avatar from a newer copy.
    public func update(_ channel: Channel) {
        guard let index = all.firstIndex(where: { $0.id == channel.id }), all[index] != channel else { return }
        all[index] = channel
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(all) { defaults.set(data, forKey: Self.defaultsKey) }
    }
}
