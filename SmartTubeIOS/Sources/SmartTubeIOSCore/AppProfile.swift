import Foundation
import Observation

// MARK: - YouTubeAccountKey

/// One YouTube identity a profile uses: a signed-in Google account (`SavedAccount.id`) on one
/// of its channels (nil `pageId` = the primary channel).
public struct YouTubeAccountKey: Codable, Hashable, Sendable {
    public var accountId: String
    public var pageId: String?

    public init(accountId: String, pageId: String?) {
        self.accountId = accountId
        self.pageId = pageId
    }

    /// The `AccountProfile` slot of this channel — the id a profile made for it gets.
    public var slot: String { AccountProfile.slot(accountId: accountId, pageId: pageId) }
}

// MARK: - AppProfile

/// A person on Who's Watching?: their YouTube accounts and Twitch accounts (several of each
/// can be active together), and their own on-device data — settings, history, watched marks,
/// follows — kept under the profile's `id` (`AccountScope` slot).
///
/// One account per service is the **main** one: the live YouTube session, watch history and
/// likes go to it.
public struct AppProfile: Codable, Identifiable, Equatable, Sendable {
    /// The `AccountScope` slot. Profiles made for a YouTube channel keep that channel's slot
    /// (data saved before profiles stays with them); new ones get `profile.<uuid>`.
    public var id: String
    public var name: String
    public var avatarURL: URL?
    /// The main channel's handle, telling apart channels that share a name and photo.
    public var handle: String?
    /// Name and picture follow the main YouTube channel until the profile is renamed.
    public var namedAfterYouTube: Bool
    public var youtube: [YouTubeAccountKey]
    public var mainYouTube: YouTubeAccountKey?
    /// Twitch user ids of the profile's signed-in Twitch accounts.
    public var twitch: [String]
    public var mainTwitch: String?

    public init(
        id: String = AppProfile.newId(), name: String, avatarURL: URL? = nil, handle: String? = nil,
        namedAfterYouTube: Bool = false, youtube: [YouTubeAccountKey] = [], mainYouTube: YouTubeAccountKey? = nil,
        twitch: [String] = [], mainTwitch: String? = nil
    ) {
        self.id = id
        self.name = name
        self.avatarURL = avatarURL
        self.handle = handle
        self.namedAfterYouTube = namedAfterYouTube
        self.youtube = youtube
        self.mainYouTube = mainYouTube
        self.twitch = twitch
        self.mainTwitch = mainTwitch
    }

    public static func newId() -> String { "profile.\(UUID().uuidString)" }

    /// The profile made for one YouTube channel (first sign-in, migration).
    init(channel: AccountProfile) {
        let key = YouTubeAccountKey(accountId: channel.accountId, pageId: channel.pageId)
        self.init(
            id: key.slot, name: channel.name, avatarURL: channel.avatarURL, handle: channel.handle,
            namedAfterYouTube: true, youtube: [key], mainYouTube: key)
    }

    /// "Name (@handle)" — for single-line lists like Settings.
    public var displayLabel: String {
        handle.map { "\(name) (\($0))" } ?? name
    }

    /// Whether the profile was made for one of `accountId`'s channels (its id is that slot).
    func isMade(for accountId: String) -> Bool {
        isMadeForAChannel && AccountProfile.accountId(ofSlot: id) == accountId
    }

    /// Made for a YouTube channel (its id is the channel's slot), not added as a person.
    var isMadeForAChannel: Bool { !id.hasPrefix("profile.") }

    var isEmpty: Bool { youtube.isEmpty && twitch.isEmpty }
}

// MARK: - ProfileStore

/// The profiles on this device and the one in use (nil = Guest). Device-wide: it decides who
/// can be picked; each profile's own data is swapped in by `AccountScope` under its id.
@MainActor
@Observable
public final class ProfileStore {
    public static let shared = ProfileStore()

    static let storageKey = "profiles.v1"

    struct Saved: Codable, Equatable {
        var profiles: [AppProfile] = []
        var activeId: String?
        /// Every YouTube channel slot already given a profile (or joined to one): a channel is
        /// only turned into a profile once, so removing it from a profile doesn't bring it back.
        var seen: Set<String> = []
        /// Google accounts added to an existing profile: their other channels don't get
        /// profiles of their own.
        var joined: Set<String> = []
    }

    public private(set) var profiles: [AppProfile] = []
    /// nil = Guest.
    public private(set) var activeId: String?
    @ObservationIgnored private var seen: Set<String> = []
    @ObservationIgnored private var joined: Set<String> = []
    /// The profile the next newly signed-in Google account joins (Add YouTube Account on a
    /// profile); nil = it gets a profile of its own.
    @ObservationIgnored public var addAccountTarget: String?
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
            let saved = try? JSONDecoder().decode(Saved.self, from: data)
        {
            profiles = saved.profiles
            activeId = saved.activeId
            seen = saved.seen
            joined = saved.joined
        }
    }

    public var active: AppProfile? { activeId.flatMap(profile(id:)) }

    public func profile(id: String) -> AppProfile? { profiles.first { $0.id == id } }

    /// The profile to show for a YouTube channel: the one it's main in, else any that uses it.
    public func profile(for key: YouTubeAccountKey) -> AppProfile? {
        profiles.first { $0.mainYouTube == key } ?? profiles.first { $0.youtube.contains(key) }
    }

    /// Makes `id` the profile in use (nil = Guest). The caller swaps the data (`AccountScope`).
    public func activate(_ id: String?) {
        guard id != activeId, id.map({ profile(id: $0) != nil }) ?? true else { return }
        activeId = id
        save()
    }

    // MARK: Editing

    /// A new person with no accounts yet (not put in use).
    @discardableResult
    public func create(name: String) -> AppProfile {
        let profile = AppProfile(name: Self.cleaned(name) ?? "Profile \(profiles.count + 1)")
        profiles.append(profile)
        save()
        return profile
    }

    /// Renames a profile; from then on its name no longer follows its main YouTube channel.
    public func rename(_ id: String, to name: String) {
        guard let name = Self.cleaned(name) else { return }
        edit(id) {
            $0.name = name
            $0.namedAfterYouTube = false
        }
    }

    /// Adds a signed-in YouTube channel to a profile (its main one if it had none).
    public func add(_ key: YouTubeAccountKey, to id: String) {
        seen.insert(key.slot)
        edit(id) { profile in
            if !profile.youtube.contains(key) { profile.youtube.append(key) }
            if profile.mainYouTube == nil { profile.mainYouTube = key }
        }
    }

    /// Takes a YouTube channel out of a profile; the next one becomes main.
    public func remove(_ key: YouTubeAccountKey, from id: String) {
        edit(id) { profile in
            profile.youtube.removeAll { $0 == key }
            if profile.mainYouTube == key { profile.mainYouTube = profile.youtube.first }
        }
    }

    public func setMain(_ key: YouTubeAccountKey, in id: String) {
        edit(id) { if $0.youtube.contains(key) { $0.mainYouTube = key } }
    }

    /// Deletes a profile that isn't in use. Its accounts stay signed in on the device.
    @discardableResult
    public func delete(_ id: String) -> Bool {
        guard id != activeId, profile(id: id) != nil else { return false }
        profiles.removeAll { $0.id == id }
        save()
        return true
    }

    private func edit(_ id: String, _ change: (inout AppProfile) -> Void) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        change(&profiles[index])
        save()
    }

    private static func cleaned(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(40))
    }

    // MARK: Sync

    /// Brings the profiles in line with the signed-in YouTube channels and the live session:
    ///
    /// 1. A newly signed-in account with `addAccountTarget` set joins that profile.
    /// 2. Every channel never seen before gets a profile of its own (unless its account joined
    ///    a profile) — what every Who's Watching? entry was before profiles.
    /// 3. Profiles named after their main channel take its current name and picture.
    /// 4. The live channel belongs to the profile in use: it becomes its main one, or the
    ///    profile it belongs to (made for it if need be) is put in use.
    public func sync(channels: [AccountProfile], live: YouTubeAccountKey?) {
        let before = snapshot
        joinTarget(live: live)
        for channel in channels {
            let key = YouTubeAccountKey(accountId: channel.accountId, pageId: channel.pageId)
            guard seen.insert(key.slot).inserted, !joined.contains(key.accountId) else { continue }
            if profile(for: key) == nil, profile(id: key.slot) == nil { profiles.append(AppProfile(channel: channel)) }
        }
        for index in profiles.indices where profiles[index].namedAfterYouTube {
            guard let main = profiles[index].mainYouTube,
                let channel = channels.first(where: { $0.accountId == main.accountId && $0.pageId == main.pageId })
            else { continue }
            profiles[index].name = channel.name
            profiles[index].avatarURL = channel.avatarURL
            profiles[index].handle = channel.handle
        }
        if let live { follow(live: live, channels: channels) }
        if snapshot != before { save() }
    }

    /// Removes a signed-out Google account from every profile. Profiles made for its channels
    /// that are left with nothing go too; their ids (slots, whose data is to be forgotten) are
    /// returned. With `replacement` (the same Google account signed in again under its
    /// original entry) the account's place in profiles goes to it instead.
    @discardableResult
    public func removeYouTubeAccount(_ accountId: String, replacement: String? = nil) -> [String] {
        var removed: [String] = []
        profiles = profiles.compactMap { profile in
            var profile = profile
            let isMadeForIt = profile.isMade(for: accountId)
            profile.youtube = profile.youtube.compactMap { key in
                guard key.accountId == accountId else { return key }
                return replacement.map { YouTubeAccountKey(accountId: $0, pageId: key.pageId) }
            }
            profile.youtube = profile.youtube.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
            if let main = profile.mainYouTube, main.accountId == accountId {
                profile.mainYouTube =
                    replacement.map { YouTubeAccountKey(accountId: $0, pageId: main.pageId) } ?? profile.youtube.first
            }
            // A channel's profile left with nothing goes (people's profiles stay); one made for
            // a replaced entry duplicates the original account's own.
            if profile.isMadeForAChannel, profile.isEmpty || (isMadeForIt && replacement != nil) {
                removed.append(profile.id)
                return nil
            }
            return profile
        }
        seen = seen.filter { AccountProfile.accountId(ofSlot: $0) != accountId }
        if joined.remove(accountId) != nil, let replacement { joined.insert(replacement) }
        if let activeId, removed.contains(activeId) { self.activeId = nil }
        save()
        return removed
    }

    // MARK: Internals

    private var snapshot: Saved { Saved(profiles: profiles, activeId: activeId, seen: seen, joined: joined) }

    private func joinTarget(live: YouTubeAccountKey?) {
        guard let target = addAccountTarget, let live else { return }
        addAccountTarget = nil
        guard let index = profiles.firstIndex(where: { $0.id == target }) else { return }
        // A new account's other channels don't become profiles; an account already on the
        // device (signed in again) just joins.
        if !seen.contains(where: { AccountProfile.accountId(ofSlot: $0) == live.accountId }) {
            joined.insert(live.accountId)
        }
        seen.insert(live.slot)
        if !profiles[index].youtube.contains(live) { profiles[index].youtube.append(live) }
        if profiles[index].mainYouTube == nil { profiles[index].mainYouTube = live }
        activeId = target
    }

    private func follow(live: YouTubeAccountKey, channels: [AccountProfile]) {
        if let index = profiles.firstIndex(where: { $0.id == activeId }), profiles[index].youtube.contains(live) {
            profiles[index].mainYouTube = live
            return
        }
        if let owner = profile(for: live) {
            activeId = owner.id
            if let index = profiles.firstIndex(where: { $0.id == owner.id }) { profiles[index].mainYouTube = live }
            return
        }
        // A channel that isn't any profile's (e.g. its profile was removed): one of its own.
        let channel =
            channels.first { $0.accountId == live.accountId && $0.pageId == live.pageId }
            ?? AccountProfile(accountId: live.accountId, pageId: live.pageId, name: "YouTube", avatarURL: nil)
        seen.insert(live.slot)
        if let index = profiles.firstIndex(where: { $0.id == live.slot }) {
            profiles[index].youtube.append(live)
            profiles[index].mainYouTube = live
        } else {
            profiles.append(AppProfile(channel: channel))
        }
        activeId = live.slot
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
