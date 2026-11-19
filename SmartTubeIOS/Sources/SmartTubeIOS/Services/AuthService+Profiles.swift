import Foundation
import SmartTubeIOSCore

// MARK: - Profiles
//
// A profile is a person (`AppProfile`): their YouTube accounts, their own on-device data. The
// live YouTube session is always the profile in use's main account (or none); everything here
// keeps the two in step. See `ProfileStore` for the rules.

extension AuthService {

    /// Who's Watching?: every profile but the hidden ones (the one in use always shows).
    public var whosWatchingAppProfiles: [AppProfile] {
        profileStore.profiles.filter { !hiddenProfileIds.contains($0.id) || $0.id == activeProfileId }
    }

    /// The profile in use's name (the account tab, Settings): "Guest", or "Sign In" on a fresh
    /// install.
    public var whoIsWatchingTitle: String {
        if let profile = profileStore.active { return profile.name }
        return profileStore.profiles.isEmpty && savedAccounts.isEmpty ? "Sign In" : "Guest"
    }

    public func setProfile(_ profile: AppProfile, hidden: Bool) {
        if hidden { hiddenProfileIds.insert(profile.id) } else { hiddenProfileIds.remove(profile.id) }
        UserDefaults.standard.set(hiddenProfileIds.sorted(), forKey: Self.hiddenProfilesKey)
    }

    /// The signed-in channel behind a profile's YouTube key (name, picture, handle).
    public func youTubeChannel(_ key: YouTubeAccountKey) -> AccountProfile? {
        profiles.first { $0.accountId == key.accountId && $0.pageId == key.pageId }
    }

    /// Signed-in channels a profile doesn't have yet.
    public func youTubeChannels(notIn profile: AppProfile) -> [AccountProfile] {
        profiles.filter { !profile.youtube.contains(YouTubeAccountKey(accountId: $0.accountId, pageId: $0.pageId)) }
    }

    /// Switches to a person's profile: their data, and their main YouTube account as the live
    /// session (signed out of YouTube when they have none). A full switch — players stop and
    /// save first, feeds reload.
    public func switchToProfile(_ profile: AppProfile) {
        guard profile.id != activeProfileId, profileStore.profile(id: profile.id) != nil else { return }
        withLiveYouTube(profile.mainYouTube, profileName: profile.name) {
            profileStore.activate(profile.id)
        }
        authLog.notice("switchToProfile() — \(profile.youtube.count) YouTube account(s)")
    }

    // MARK: Editing

    @discardableResult
    public func createProfile(named name: String) -> AppProfile {
        profileStore.create(name: name)
    }

    public func renameProfile(_ profile: AppProfile, to name: String) {
        profileStore.rename(profile.id, to: name)
    }

    /// Adds an already signed-in channel to a profile. The profile in use with no YouTube yet
    /// goes live on it.
    public func addYouTube(_ key: YouTubeAccountKey, to profile: AppProfile) {
        let goesLive = profile.id == activeProfileId && profile.mainYouTube == nil
        guard goesLive else {
            profileStore.add(key, to: profile.id)
            return
        }
        withLiveYouTube(key, profileName: profile.name) { profileStore.add(key, to: profile.id) }
    }

    /// Takes a channel out of a profile (it stays signed in on the device). Removing the profile
    /// in use's live channel moves the session to its next one, or ends it.
    public func removeYouTube(_ key: YouTubeAccountKey, from profile: AppProfile) {
        guard profile.id == activeProfileId, profile.mainYouTube == key else {
            profileStore.remove(key, from: profile.id)
            return
        }
        let next = profile.youtube.first { $0 != key }
        withLiveYouTube(next, profileName: profile.name) { profileStore.remove(key, from: profile.id) }
    }

    /// Makes a channel the profile's main one: for the profile in use, the live session.
    public func makeMainYouTube(_ key: YouTubeAccountKey, in profile: AppProfile) {
        guard key != profile.mainYouTube else { return }
        guard profile.id == activeProfileId else {
            profileStore.setMain(key, in: profile.id)
            return
        }
        withLiveYouTube(key, profileName: profile.name) { profileStore.setMain(key, in: profile.id) }
    }

    /// Signs in a new Google account for `profile` (switching to it first): the account joins
    /// it instead of getting profiles of its own. Present the sign-in screen next; cancelling
    /// goes back as with Add Account.
    public func prepareToAddYouTubeAccount(to profile: AppProfile) {
        if profile.id != activeProfileId { switchToProfile(profile) }
        profileStore.addAccountTarget = profile.id
        prepareToAddAccount()
    }

    /// Deletes a profile and its on-device data; its accounts stay signed in. The profile in
    /// use is left for Guest first.
    public func deleteProfile(_ profile: AppProfile) {
        if profile.id == activeProfileId { switchToGuest() }
        guard profileStore.delete(profile.id) else { return }
        hiddenProfileIds.remove(profile.id)
        UserDefaults.standard.set(hiddenProfileIds.sorted(), forKey: Self.hiddenProfilesKey)
        // After the switch above has parked the profile's data.
        let slot = profile.id
        Task { @MainActor in AccountScope.forget(slots: [slot]) }
    }

    // MARK: Internals

    /// Makes `key` the live YouTube session (nil = none) and applies `change` to the profiles
    /// before the profile in use's data is synced — without the session change pulling another
    /// profile in on the way (see `syncAccountScope`).
    func withLiveYouTube(_ key: YouTubeAccountKey?, profileName: String, then change: () -> Void) {
        isSwitchingProfile = true
        defer {
            isSwitchingProfile = false
            syncAccountScope()
        }
        let target = key.flatMap { key in savedAccounts.contains { $0.id == key.accountId } ? key : nil }
        if let target, isSignedIn, target.accountId == activeAccountId {
            if target.pageId != activePageId {
                let channel =
                    channels.first { $0.pageId == target.pageId }
                    ?? YouTubeChannel(name: profileName, avatarURL: nil, pageId: target.pageId)
                selectChannel(channel)
            } else {
                beginAccountChange()
            }
        } else if let target {
            switchAccount(to: target.accountId, pageId: .some(target.pageId))
        } else {
            beginAccountChange()
            endYouTubeSession()
        }
        change()
    }
}
