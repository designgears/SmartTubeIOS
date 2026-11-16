import Foundation
import SmartTubeIOSCore

#if canImport(WebKit)
import WebKit
#endif

// MARK: - Multiple accounts
//
// The active account uses the regular token/Keychain properties; `savedAccounts` holds every
// signed-in account (active included) so switching needs no new sign-in. Switching swaps the
// tokens, the Brand Account selection and the SAPISID, and clears YouTube/Google cookies that
// belonged to the previous account. Observers of `accessToken` (InnerTubeAPI, feeds) reload.

extension AuthService {

    /// Starts an account change: in-flight auth work for the previous account becomes stale,
    /// and players stop and save progress while the previous account is still live.
    func beginAccountChange() {
        accountGeneration += 1
        NotificationCenter.default.post(name: AccountScope.willChangeNotification, object: nil)
    }

    /// Every profile on Who's Watching?: one per channel of each signed-in account.
    public var profiles: [AccountProfile] {
        savedAccounts.flatMap { account in
            AccountProfile.profiles(for: account, liveChannels: account.id == activeAccountId ? channels : nil)
        }
    }

    /// The profiles Who's Watching? shows: all but the hidden ones (the one in use always shows).
    public var whosWatchingProfiles: [AccountProfile] {
        AccountProfile.shown(profiles, hidden: hiddenProfileIds, activeId: activeProfileId)
    }

    /// Hides a profile from (or shows it again on) Who's Watching?. It stays signed in and
    /// reachable from Settings.
    public func setProfile(_ profile: AccountProfile, hidden: Bool) {
        if hidden { hiddenProfileIds.insert(profile.id) } else { hiddenProfileIds.remove(profile.id) }
        persistHiddenProfiles()
    }

    /// A signed-out account's profiles no longer need a hidden flag.
    func forgetHiddenProfiles(of accountId: String) {
        let before = hiddenProfileIds
        hiddenProfileIds = hiddenProfileIds.filter { AccountProfile.accountId(ofSlot: $0) != accountId }
        if hiddenProfileIds != before { persistHiddenProfiles() }
    }

    private func persistHiddenProfiles() {
        UserDefaults.standard.set(hiddenProfileIds.sorted(), forKey: Self.hiddenProfilesKey)
    }

    /// The active profile's id (AccountScope slot), nil for Guest.
    public var activeProfileId: String? {
        guard isSignedIn, let activeAccountId else { return nil }
        return AccountProfile.slot(accountId: activeAccountId, pageId: activePageId)
    }

    /// Switches to a profile: another account (on the given channel), or another channel of
    /// the active account. Either way it's a full switch — own data, fresh YouTube session.
    public func switchProfile(_ profile: AccountProfile) {
        guard profile.id != activeProfileId else { return }
        if isSignedIn, profile.accountId == activeAccountId {
            let channel =
                channels.first { $0.pageId == profile.pageId }
                ?? YouTubeChannel(name: profile.name, avatarURL: profile.avatarURL, pageId: profile.pageId)
            selectChannel(channel)
        } else {
            switchAccount(to: profile.accountId, pageId: .some(profile.pageId))
        }
    }

    public var activeAccount: SavedAccount? {
        savedAccounts.first { $0.id == activeAccountId }
    }

    /// Switches to another signed-in account, on `pageId` when given (`.some(nil)` = primary
    /// channel), otherwise on the channel it last used.
    public func switchAccount(to id: String, pageId requestedPageId: String?? = .none) {
        guard id != activeAccountId || !isSignedIn,
            let target = savedAccounts.first(where: { $0.id == id })
        else { return }
        beginAccountChange()
        if isSignedIn, activeAccountId != nil { rememberActiveAccount() }

        pollTask?.cancel()
        pollTask = nil
        pendingActivation = nil
        accountToRestoreOnCancel = nil
        clearAccountCookies()
        resetChannels()

        activeAccountId = target.id
        refreshToken = target.refreshToken
        tokenExpiry = target.tokenExpiry
        let pageId = requestedPageId ?? target.pageId
        let channel = target.channels?.first { $0.pageId == pageId }
        accountName = channel?.name ?? target.displayName
        accountAvatarURL = channel?.avatarURL ?? target.displayAvatarURL
        sapisid = target.sapisid
        gaiaId = target.gaiaId
        // An expired access token is dropped; scheduleProactiveRefresh() refreshes at once.
        if let expiry = target.tokenExpiry, expiry > Date() {
            accessToken = target.accessToken
        } else {
            accessToken = nil
        }
        isSignedIn = refreshToken != nil || accessToken != nil || target.isLocalOnly
        // No channel-change notification: feeds reload on AccountScope's didChange, once the
        // incoming account's on-device data is live.
        setActivePageId(pageId, notify: false)
        let sapisidValue = target.sapisid
        Task { await tokenManager.setSAPISID(sapisidValue) }
        saveToKeychain()
        // saveToKeychain → rememberActiveAccount syncs too, but skips token-less local profiles.
        syncAccountScope()
        scheduleProactiveRefresh()
        authLog.notice("switchAccount() — now \(self.accountName ?? "unknown") (\(self.savedAccounts.count) accounts)")

        guard !target.isLocalOnly else { return }  // no Google login: nothing to fetch
        Task {
            do { try await fetchUserInfo() } catch {
                authLog.error("switchAccount() fetchUserInfo failed: \(String(describing: error))")
            }
            if sapisid == nil { await fetchYouTubeWebCookies() }
        }
    }

    /// Call before presenting sign-in to add another account. The current account stays
    /// saved; cancelling (`cancelSignIn()`) switches back to it.
    public func prepareToAddAccount() {
        guard isSignedIn else { return }  // first account: normal sign-in
        beginAccountChange()
        rememberActiveAccount()
        let previous = activeAccountId
        clearSession()
        clearAccountCookies()
        activeAccountId = nil  // in memory only; persisted once the new account signs in
        accountToRestoreOnCancel = previous
    }

    /// Guest: use the app signed out without signing anyone out. Saved accounts stay one
    /// tap away, and Guest has its own on-device data (AccountScope's "guest" slot).
    public var isGuest: Bool { !isSignedIn }

    public func switchToGuest() {
        guard isSignedIn else { return }
        beginAccountChange()
        rememberActiveAccount()
        clearSession()
        clearAccountCookies()
        activeAccountId = nil
        accountToRestoreOnCancel = nil
        // Active-session keys only; the saved accounts (vault) are untouched.
        Task { await tokenManager.clearToken() }
        ActiveChannel.shared.set(pageId: nil)
        persistSavedAccounts()
        syncAccountScope()
        authLog.notice("switchToGuest() — \(self.savedAccounts.count) account(s) kept")
    }

    /// Signs one account out of this device (switching to another if it was active).
    public func removeAccount(_ id: String) {
        if id == activeAccountId {
            signOut()
            return
        }
        savedAccounts.removeAll { $0.id == id }
        persistSavedAccounts()
        AccountScope.forget(id)
        forgetHiddenProfiles(of: id)
    }

    // MARK: UI testing

    /// `--uitesting --uitesting-fake-accounts` adds two local-only profiles ("Alex", "Sam") — no
    /// Google login, so feeds load signed out like Guest — to drive account switching end to end
    /// in UI tests. `--uitesting-fake-account-active=<uitest-alex|uitest-sam|guest>` picks who is
    /// active at launch. Returns false (and does nothing) outside UI tests.
    func seedFakeAccountsForUITesting() -> Bool {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("--uitesting"), args.contains("--uitesting-fake-accounts") else { return false }
        func profile(_ id: String, _ name: String) -> SavedAccount {
            var account = SavedAccount(id: id)
            account.displayName = name
            account.primaryName = name
            account.localOnly = true
            return account
        }
        var alex = profile("uitest-alex", "Alex")
        // Alex also has a Brand channel, so channel profiles can be exercised.
        alex.channels = [
            YouTubeChannel(name: "Alex", avatarURL: nil, pageId: nil),
            YouTubeChannel(name: "Alex Kids", avatarURL: nil, pageId: "uitest-kids"),
        ]
        savedAccounts = [alex, profile("uitest-sam", "Sam")]
        let prefix = "--uitesting-fake-account-active="
        let activeId = args.first { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) } ?? "uitest-alex"
        if let active = savedAccounts.first(where: { $0.id == activeId }) {
            activeAccountId = active.id
            accountName = active.displayName
            isSignedIn = true
        } else {
            activeAccountId = nil
            isSignedIn = false
        }
        authLog.notice("[uitesting] local test profiles seeded — active=\(activeId)")
        syncAccountScope()
        return true
    }

    // MARK: Internals

    /// Copies the active session into `savedAccounts` (creating the entry on first use).
    func rememberActiveAccount() {
        guard isSignedIn, accessToken != nil || refreshToken != nil else { return }
        var entry = savedAccounts.first { $0.id == activeAccountId } ?? SavedAccount()
        entry.displayName = accountName
        entry.displayAvatarURL = accountAvatarURL
        if let primary = channels.first(where: { $0.isPrimary }) {
            entry.primaryName = primary.name
        } else if entry.primaryName == nil, activePageId == nil {
            entry.primaryName = accountName
        }
        if let gaiaId { entry.gaiaId = gaiaId }
        if !channels.isEmpty { entry.channels = channels }
        entry.accessToken = accessToken
        entry.refreshToken = refreshToken
        entry.tokenExpiry = tokenExpiry
        entry.sapisid = sapisid
        entry.pageId = activePageId
        // The same Google account signed in again keeps its ORIGINAL entry id, so the
        // on-device data saved under that id (AccountScope) comes back with it; the
        // short-lived new entry and its data are dropped.
        var droppedId: String?
        if let original = savedAccounts.first(where: { $0.id != entry.id && $0.isSameGoogleAccount(as: entry) }) {
            authLog.notice("[accounts] \(entry.displayName ?? "account") signed in again — keeping its existing entry")
            droppedId = entry.id
            savedAccounts.removeAll { $0.id == entry.id }
            entry.id = original.id
        }
        if let index = savedAccounts.firstIndex(where: { $0.id == entry.id }) {
            savedAccounts[index] = entry
        } else {
            savedAccounts.append(entry)
            authLog.notice("[accounts] saved new account entry (\(self.savedAccounts.count) total)")
        }
        activeAccountId = entry.id
        accountToRestoreOnCancel = nil
        persistSavedAccounts()
        syncAccountScope()
        // After the switch above has parked the temporary entry's data, delete it.
        if let droppedId { Task { @MainActor in AccountScope.forget(droppedId) } }
    }

    /// Makes the active account's on-device data (history, positions, queue, settings…)
    /// live — see `AccountScope`. Signed out uses its own "guest" data.
    func syncAccountScope() {
        // While adding an account the previous one stays live until the new one signs in.
        if activeAccountId == nil, accountToRestoreOnCancel != nil { return }
        // Each channel of an account is its own profile (primary = the bare account id).
        let slot = activeProfileId
        Task { @MainActor in await AccountScope.activate(slot) }
    }

    func loadSavedAccounts() {
        savedAccounts = tokenManager.initialSavedAccounts
        activeAccountId = tokenManager.initialActiveAccountId
        // One-time cleanup: builds before this fix could stamp a new account's entry with the
        // previous account's Google id. Drop stored ids; each account re-learns its verified
        // id (fetchYouTubeWebCookies) the next time it is active.
        let migrationKey = "accounts.gaiaIdReset.v1"
        if !UserDefaults.standard.bool(forKey: migrationKey) {
            for index in savedAccounts.indices { savedAccounts[index].gaiaId = nil }
            UserDefaults.standard.set(true, forKey: migrationKey)
            persistSavedAccounts()
        }
        // Syncs the vault with the active keys (and migrates single-account installs).
        if isSignedIn { rememberActiveAccount() } else { syncAccountScope() }
    }

    func persistSavedAccounts() {
        let accounts = savedAccounts
        let activeId = activeAccountId
        Task { await tokenManager.setSavedAccounts(accounts, activeId: activeId) }
    }

    /// YouTube/Google web state belongs to one account; drop it when the account changes:
    /// cookies (youtube, google, googlevideo, youtube-nocookie) and, in WebKit, every kind of
    /// site data (localStorage, IndexedDB — where YouTube keeps its BotGuard state — caches).
    func clearAccountCookies() {
        for cookie in HTTPCookieStorage.shared.cookies ?? []
        where cookie.domain.contains("youtube") || cookie.domain.contains("google") {
            HTTPCookieStorage.shared.deleteCookie(cookie)
        }
        #if canImport(WebKit)
        BotGuardWebViewRunner.shared.resetForAccountChange()
        YouTubeWebViewHLSExtractor.shared.resetForAccountChange()
        let store = WKWebsiteDataStore.default()
        let allTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        store.fetchDataRecords(ofTypes: allTypes) { records in
            let accountRecords = records.filter {
                $0.displayName.contains("youtube") || $0.displayName.contains("google")
            }
            store.removeData(ofTypes: allTypes, for: accountRecords) {}
        }
        #endif
    }
}
