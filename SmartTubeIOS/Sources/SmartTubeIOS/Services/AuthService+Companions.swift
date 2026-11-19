import Foundation
import SmartTubeIOSCore

// MARK: - Companion accounts
//
// The profile in use's YouTube accounts other than the live session (see `CompanionAccounts`).
// Each is read through its own `InnerTubeAPI` with its own token, refreshed here from the
// account's saved refresh token and written back to the vault. Only the live session uses the
// regular token properties, cookies and BotGuard state.

extension AuthService {

    /// Hands `CompanionAccounts` its accounts (called once, from `init`).
    func installCompanionProvider() {
        CompanionAccounts.shared.provider = { [weak self] in await self?.companionAPIs() ?? [] }
    }

    /// The profile in use's other YouTube channels.
    var companionKeys: [YouTubeAccountKey] {
        guard let profile = profileStore.active else { return [] }
        let live = isSignedIn ? activeAccountId.map { YouTubeAccountKey(accountId: $0, pageId: activePageId) } : nil
        return profile.youtube.filter { key in key != live && savedAccounts.contains { $0.id == key.accountId } }
    }

    /// One API per companion channel whose account has a usable token.
    func companionAPIs() async -> [any InnerTubeAPIProtocol] {
        var apis: [any InnerTubeAPIProtocol] = []
        for key in companionKeys {
            guard let token = await companionToken(for: key.accountId) else { continue }
            let cacheKey = "\(key.slot)|\(token)"
            if let api = companionAPICache[cacheKey] {
                apis.append(api)
            } else {
                let api = InnerTubeAPI.companion(authToken: token, pageId: key.pageId)
                companionAPICache = companionAPICache.filter { !$0.key.hasPrefix("\(key.slot)|") }
                companionAPICache[cacheKey] = api
                apis.append(api)
            }
        }
        return apis
    }

    /// A companion account's access token: the saved one while it's fresh, else refreshed (one
    /// refresh per account at a time). nil when it can't be had (no refresh token, revoked).
    func companionToken(for accountId: String) async -> String? {
        guard let account = savedAccounts.first(where: { $0.id == accountId }), !account.isLocalOnly else { return nil }
        if let token = account.accessToken, let expiry = account.tokenExpiry, expiry.timeIntervalSinceNow > 5 * 60 {
            return token
        }
        if let running = companionRefreshes[accountId] { return await running.value }
        guard let refresh = account.refreshToken else { return nil }
        let task = Task { await self.refreshCompanionToken(accountId: accountId, refreshToken: refresh) }
        companionRefreshes[accountId] = task
        let token = await task.value
        companionRefreshes[accountId] = nil
        return token
    }

    private func refreshCompanionToken(accountId: String, refreshToken: String) async -> String? {
        let creds = await credentialsFetcher.credentials()
        var request = URLRequest(url: Self.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formEncode([
            "refresh_token": refreshToken, "client_id": creds.clientId, "client_secret": creds.clientSecret,
            "grant_type": "refresh_token",
        ])
        guard let (data, response) = try? await URLSession.shared.data(for: request),
            (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? false,
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let token = json["access_token"] as? String
        else {
            authLog.error("companion token refresh failed")
            return nil
        }
        // Saved back unless the account became the live session meanwhile (its own refresh
        // owns the tokens then).
        if accountId != activeAccountId, let index = savedAccounts.firstIndex(where: { $0.id == accountId }) {
            savedAccounts[index].accessToken = token
            savedAccounts[index].tokenExpiry = (json["expires_in"] as? TimeInterval).map {
                Date().addingTimeInterval($0 - 60)
            }
            persistSavedAccounts()
        }
        return token
    }
}
