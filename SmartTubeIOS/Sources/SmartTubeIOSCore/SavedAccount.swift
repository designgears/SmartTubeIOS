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

    public init(id: String = UUID().uuidString) {
        self.id = id
    }

    /// True when `other` is the same Google account (re-added), not just the same entry.
    public func isSameGoogleAccount(as other: SavedAccount) -> Bool {
        if let a = gaiaId, let b = other.gaiaId { return a == b }
        if let a = primaryName, let b = other.primaryName, !a.isEmpty {
            return a.caseInsensitiveCompare(b) == .orderedSame
        }
        return false
    }
}
