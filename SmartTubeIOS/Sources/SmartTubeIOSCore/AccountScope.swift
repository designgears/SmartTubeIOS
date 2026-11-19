import Foundation
import os

private let scopeLog = Logger(subsystem: appSubsystem, category: "AccountScope")

// MARK: - AccountScope
//
// Makes everything the app keeps on the device belong to the active account: watch
// positions, local history, search history, local subscriptions and RSS feeds, the play
// queue, Watch Later tracking and all settings. Signed out ("Guest") is its own slot.
//
// Each store swaps its own data inside its own isolation (`exchange`): its live in-memory
// value is parked under the outgoing account and the incoming account's value replaces it in
// one step, so a write racing the switch can't land the old account's data on the new one.

public enum AccountScope {
    /// `SettingsStore`'s key (app target).
    public static let settingsKey = "smarttube_app_settings"

    static let guestSlot = "guest"
    static let currentSlotKey = "accountScope.currentSlot"

    /// Posted synchronously *before* anything changes, while the outgoing account's tokens
    /// and data are still live — players stop and save progress here.
    public static let willChangeNotification = Notification.Name("AccountScopeWillChange")
    /// Posted on the main actor after every store holds the incoming account's data.
    /// `userInfo["isNewAccount"]` is true when that account had no saved data yet.
    public static let didChangeNotification = Notification.Name("AccountScopeDidChange")

    /// Settings live in the app target; `SettingsStore` installs its switcher here. Called
    /// synchronously on the main actor: (outgoing slot or nil on first run, incoming, isNew).
    @MainActor public static var settingsSwitcher: ((String?, String, Bool) -> Void)?

    static func slotKey(_ key: String, slot: String) -> String { "\(key)#account.\(slot)" }

    /// The slot whose data is live right now.
    public static var currentSlot: String? { UserDefaults.standard.string(forKey: currentSlotKey) }

    /// Store helper: parks `current` (the store's live value; nil = nothing) under the
    /// outgoing slot and returns the incoming slot's saved value, removing its parked copy.
    /// `outgoing == nil` (first run) discards `current`: data from before account scoping
    /// can't be attributed to an account, so it isn't handed to whoever is signed in.
    public static func exchange(
        key: String, current: Any?, outgoing: String?, incoming: String, defaults: UserDefaults = .standard
    ) -> Any? {
        if let outgoing {
            if let current {
                defaults.set(current, forKey: slotKey(key, slot: outgoing))
            } else {
                defaults.removeObject(forKey: slotKey(key, slot: outgoing))
            }
        }
        let incomingKey = slotKey(key, slot: incoming)
        let saved = defaults.object(forKey: incomingKey)
        defaults.removeObject(forKey: incomingKey)
        return saved
    }

    /// Makes `accountId`'s data live (nil = Guest). Returns false when nothing changed.
    @MainActor @discardableResult
    public static func activate(_ accountId: String?, defaults: UserDefaults = .standard) async -> Bool {
        let incoming = accountId ?? guestSlot
        let outgoing = defaults.string(forKey: currentSlotKey)
        guard outgoing != incoming else { return false }
        // Recorded first, so a second activation queued behind this one sees the new state.
        defaults.set(incoming, forKey: currentSlotKey)
        let isNewAccount = outgoing == nil || !hasSavedData(incoming, defaults: defaults)
        scopeLog.notice(
            "switching account data \(outgoing ?? "unattributed", privacy: .public) → \(incoming, privacy: .public) (new=\(isNewAccount, privacy: .public))"
        )

        settingsSwitcher?(outgoing, incoming, isNewAccount)
        LocalWatchHistoryStore.shared.switchAccountData(from: outgoing, to: incoming)
        WatchedStore.shared.switchAccountData(from: outgoing, to: incoming)
        WatchLaterMembershipStore.shared.switchAccountData(from: outgoing, to: incoming)
        await VideoStateStore.shared.switchAccountData(from: outgoing, to: incoming)
        await SearchHistoryStore.shared.switchAccountData(from: outgoing, to: incoming)
        await LocalSubscriptionStore.shared.switchAccountData(from: outgoing, to: incoming)
        await CurrentQueueStore.shared.switchAccountData(from: outgoing, to: incoming)
        await RSSFeedStore.shared.switchAccountData(from: outgoing, to: incoming)
        await ContinueWatchingStore.shared.switchAccountData(from: outgoing, to: incoming)
        ExternalFollowStore.shared.switchAccountData(from: outgoing, to: incoming)
        ExternalLiveStore.shared.reset()
        // Prefetched player/next responses (memory and disk) were fetched for the old account.
        await VideoPreloadCache.shared.removeAll()

        NotificationCenter.default.post(
            name: didChangeNotification, object: nil, userInfo: ["isNewAccount": isNewAccount])
        return true
    }

    /// Deletes a removed account's parked data — every channel profile of it.
    @MainActor
    public static func forget(_ accountId: String, defaults: UserDefaults = .standard) {
        WatchedStore.shared.forget(accountId: accountId)
        let live = defaults.string(forKey: currentSlotKey)
        let exact = "#account.\(accountId)"
        let channelPrefix = "#account.\(accountId).channel."
        for key in defaults.dictionaryRepresentation().keys {
            guard key.hasSuffix(exact) || key.contains(channelPrefix) else { continue }
            if let live, key.hasSuffix("#account.\(live)") { continue }  // never the live profile
            defaults.removeObject(forKey: key)
        }
    }

    /// Deletes removed profiles' parked data (exact slots; never the live one).
    @MainActor
    public static func forget(slots: [String], defaults: UserDefaults = .standard) {
        let live = defaults.string(forKey: currentSlotKey)
        let suffixes = Set(slots.filter { $0 != live }.map { "#account.\($0)" })
        guard !suffixes.isEmpty else { return }
        for slot in slots where slot != live { WatchedStore.shared.forget(slot: slot) }
        for key in defaults.dictionaryRepresentation().keys {
            guard let hash = key.range(of: "#account.", options: .backwards) else { continue }
            if suffixes.contains(String(key[hash.lowerBound...])) { defaults.removeObject(forKey: key) }
        }
    }

    static func hasSavedData(_ slot: String, defaults: UserDefaults) -> Bool {
        let suffix = "#account.\(slot)"
        return defaults.dictionaryRepresentation().keys.contains { $0.hasSuffix(suffix) }
    }
}
