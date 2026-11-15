import Foundation
import SmartTubeIOSCore

extension AuthService {

    // MARK: - Channels (Brand Accounts)

    public var activeChannel: YouTubeChannel? {
        channels.first { $0.pageId == activePageId }
    }

    /// Switches every InnerTube request to `channel`. The OAuth token stays the primary
    /// account's; only `X-Goog-Pageid` changes, so no new sign-in is needed.
    /// Each channel is its own profile: switching channel is a full profile switch (players
    /// stop first, the channel's own on-device data and a fresh YouTube session), and the
    /// account remembers the channel for next time.
    public func selectChannel(_ channel: YouTubeChannel) {
        guard channel.pageId != activePageId else { return }
        authLog.notice("selectChannel() — \(channel.isPrimary ? "primary" : "brand account")")
        beginAccountChange()
        setActivePageId(channel.pageId, notify: false)
        accountName = channel.name
        accountAvatarURL = channel.avatarURL
        saveToKeychain()
        syncAccountScope()  // also for profiles rememberActiveAccount skips (no tokens)
    }

    /// accounts_list is only fetched at sign-in, so the list is empty after a relaunch.
    public func loadChannelsIfNeeded() async {
        guard isSignedIn, channels.isEmpty else { return }
        do { try await fetchUserInfo() } catch {
            authLog.error("loadChannelsIfNeeded() failed: \(String(describing: error))")
        }
    }

    /// Applies the accounts_list result; drops a stored pageId the account no longer has.
    func applyChannels(_ list: [YouTubeChannel]) {
        guard !list.isEmpty else { return }
        channels = list
        if let pageId = activePageId, !list.contains(where: { $0.pageId == pageId }) {
            authLog.notice("applyChannels() — stored Brand Account not found, back to primary")
            setActivePageId(nil)
            syncAccountScope()  // the primary channel is a different profile
        }
    }

    func setActivePageId(_ pageId: String?, notify: Bool = true) {
        activePageId = pageId
        ActiveChannel.shared.set(pageId: pageId)
        Task { await tokenManager.setPageId(pageId) }
        if notify { NotificationCenter.default.post(name: .activeChannelDidChange, object: nil) }
    }

    func resetChannels() {
        channels = []
        activePageId = nil
        ActiveChannel.shared.set(pageId: nil)
    }
}
