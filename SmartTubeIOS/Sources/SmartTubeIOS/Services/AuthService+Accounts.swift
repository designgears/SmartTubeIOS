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

    public var activeAccount: SavedAccount? {
        savedAccounts.first { $0.id == activeAccountId }
    }

    /// Switches to another signed-in account.
    public func switchAccount(to id: String) {
        guard id != activeAccountId || !isSignedIn,
            let target = savedAccounts.first(where: { $0.id == id })
        else { return }
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
        setActivePageId(target.pageId)  // also tells the UI to return Home
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
        rememberActiveAccount()
        let previous = activeAccountId
        clearSession()
        clearAccountCookies()
        activeAccountId = nil  // in memory only; persisted once the new account signs in
        accountToRestoreOnCancel = previous
    }

    /// Signs one account out of this device (switching to another if it was active).
    public func removeAccount(_ id: String) {
        if id == activeAccountId {
            signOut()
            return
        }
        savedAccounts.removeAll { $0.id == id }
        persistSavedAccounts()
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
        // The same Google account signed in twice keeps a single entry.
        savedAccounts.removeAll { $0.id != entry.id && $0.isSameGoogleAccount(as: entry) }
        if let index = savedAccounts.firstIndex(where: { $0.id == entry.id }) {
            savedAccounts[index] = entry
        } else {
            savedAccounts.append(entry)
        }
        activeAccountId = entry.id
        accountToRestoreOnCancel = nil
        persistSavedAccounts()
    }

    func loadSavedAccounts() {
        savedAccounts = tokenManager.initialSavedAccounts
        activeAccountId = tokenManager.initialActiveAccountId
        // Syncs the vault with the active keys (and migrates single-account installs).
        if isSignedIn { rememberActiveAccount() }
    }

    func persistSavedAccounts() {
        let accounts = savedAccounts
        let activeId = activeAccountId
        Task { await tokenManager.setSavedAccounts(accounts, activeId: activeId) }
    }

    /// YouTube/Google cookies belong to one account; drop them when the account changes.
    func clearAccountCookies() {
        for cookie in HTTPCookieStorage.shared.cookies ?? []
        where cookie.domain.contains("youtube.") || cookie.domain.contains("google.") {
            HTTPCookieStorage.shared.deleteCookie(cookie)
        }
        #if canImport(WebKit)
        WKWebsiteDataStore.default().removeData(
            ofTypes: [WKWebsiteDataTypeCookies], modifiedSince: Date(timeIntervalSince1970: 0)
        ) {}
        #endif
    }
}
