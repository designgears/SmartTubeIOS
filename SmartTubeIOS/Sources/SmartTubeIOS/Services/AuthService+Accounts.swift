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

    public var activeAccount: SavedAccount? {
        savedAccounts.first { $0.id == activeAccountId }
    }

    /// Switches to another signed-in account.
    public func switchAccount(to id: String) {
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
        accountName = target.displayName
        accountAvatarURL = target.displayAvatarURL
        sapisid = target.sapisid
        gaiaId = target.gaiaId
        // An expired access token is dropped; scheduleProactiveRefresh() refreshes at once.
        if let expiry = target.tokenExpiry, expiry > Date() {
            accessToken = target.accessToken
        } else {
            accessToken = nil
        }
        isSignedIn = refreshToken != nil || accessToken != nil
        // No channel-change notification: feeds reload on AccountScope's didChange, once the
        // incoming account's on-device data is live.
        setActivePageId(target.pageId, notify: false)
        let sapisidValue = target.sapisid
        Task { await tokenManager.setSAPISID(sapisidValue) }
        saveToKeychain()
        scheduleProactiveRefresh()
        authLog.notice("switchAccount() — now \(self.accountName ?? "unknown") (\(self.savedAccounts.count) accounts)")

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
        let accountId = isSignedIn ? activeAccountId : nil
        Task { @MainActor in await AccountScope.activate(accountId) }
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
