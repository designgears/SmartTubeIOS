import Foundation

/// A Google account signed in on this device. The *active* account also lives in
/// `TokenManager`'s regular Keychain entries; every signed-in account (active included) is
/// kept here so the user can switch between them without signing in again.
public struct SavedAccount: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    /// Name / avatar shown for the account (the selected Brand Account when one is active).
    public var displayName: String?
    public var displayAvatarURL: URL?
    /// The Google account's primary channel name — used to recognise the same account
    /// signing in again (together with `gaiaId` when known).
    public var primaryName: String?
    public var gaiaId: String?
    public var accessToken: String?
    public var refreshToken: String?
    public var tokenExpiry: Date?
    public var sapisid: String?
    /// Selected Brand Account for this login (nil = primary).
    public var pageId: String?
    /// A profile with no Google login (UI tests): its own on-device data, signed-out API calls.
    public var localOnly: Bool?
    /// The account's channels (primary + Brand Accounts), saved whenever the account is active,
    /// so Who's Watching? can offer each channel as its own profile.
    public var channels: [YouTubeChannel]?
    public var isLocalOnly: Bool { localOnly == true }

    public init(id: String = UUID().uuidString) {
        self.id = id
    }

    /// True when `other` is the same Google account (re-added), not just the same entry.
    /// Only the verified Google account id (`sub`) counts. Display names are never used:
    /// different accounts can share a name, and a wrong match deletes an account.
    public func isSameGoogleAccount(as other: SavedAccount) -> Bool {
        guard let mine = gaiaId, let theirs = other.gaiaId else { return false }
        return mine == theirs
    }
}

// MARK: - AccountProfile

/// One entry on Who's Watching?: a Google account's channel (primary or Brand Account).
/// Each profile has its own on-device data (`slot`) and YouTube session.
public struct AccountProfile: Identifiable, Equatable, Sendable {
    public let accountId: String
    /// nil = the account's primary channel.
    public let pageId: String?
    public let name: String
    public let avatarURL: URL?
    /// The channel's handle — what tells apart channels that share a name and photo.
    public let handle: String?

    public init(accountId: String, pageId: String?, name: String, avatarURL: URL?, handle: String? = nil) {
        self.accountId = accountId
        self.pageId = pageId
        self.name = name
        self.avatarURL = avatarURL
        self.handle = handle
    }

    /// "Name (@handle)" — for single-line lists like Settings.
    public var displayLabel: String {
        handle.map { "\(name) (\($0))" } ?? name
    }

    public var id: String { Self.slot(accountId: accountId, pageId: pageId) }

    /// AccountScope slot. The primary channel uses the bare account id (data saved before
    /// channels were profiles stays with it); Brand channels get their own slot.
    public static func slot(accountId: String, pageId: String?) -> String {
        pageId.map { "\(accountId)\(channelSeparator)\($0)" } ?? accountId
    }

    private static let channelSeparator = ".channel."

    /// The account a profile slot belongs to (inverse of `slot(accountId:pageId:)`).
    public static func accountId(ofSlot slot: String) -> String {
        slot.range(of: channelSeparator).map { String(slot[..<$0.lowerBound]) } ?? slot
    }

    /// The profiles shown on Who's Watching?: hidden ones are left out, except the one in
    /// use, so the current profile never disappears from under the user.
    public static func shown(
        _ profiles: [AccountProfile], hidden: Set<String>, activeId: String?
    )
        -> [AccountProfile]
    {
        profiles.filter { !hidden.contains($0.id) || $0.id == activeId }
    }

    /// The profiles an account offers: one per known channel, or a single profile when its
    /// channels aren't known yet (it hasn't been active since channels were saved).
    public static func profiles(
        for account: SavedAccount, liveChannels: [YouTubeChannel]? = nil
    )
        -> [AccountProfile]
    {
        let channels = (liveChannels?.isEmpty == false ? liveChannels : account.channels) ?? []
        guard channels.count > 1 else {
            return [
                AccountProfile(
                    accountId: account.id, pageId: nil,
                    name: account.primaryName ?? account.displayName ?? "Account",
                    avatarURL: channels.first?.avatarURL ?? account.displayAvatarURL,
                    handle: channels.first?.handle)
            ]
        }
        return channels.map {
            AccountProfile(
                accountId: account.id, pageId: $0.pageId, name: $0.name, avatarURL: $0.avatarURL, handle: $0.handle)
        }
    }
}
