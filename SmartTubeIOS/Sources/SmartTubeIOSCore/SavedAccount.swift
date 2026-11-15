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
