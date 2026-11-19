/// Accessibility identifiers, for UI tests. One definition each (AGENTS.md); add new ones here.
enum AccessibilityID {
    enum Channels {
        static let sortMenu = "channels.sortMenu"
    }

    enum Settings {
        static let accentColorPicker = "settings.accentColorPicker"
        static let accountsLink = "settings.accountsLink"
        static let addAccountButton = "settings.addAccountButton"
        static let changePINButton = "settings.changePINButton"
        static let watchedBarColorPicker = "settings.watchedBarColorPicker"
        static let blockTwitchAdsToggle = "settings.blockTwitchAdsToggle"
        static let chatEmotesToggle = "settings.chatEmotesToggle"
        static let thirdPartyEmotesToggle = "settings.thirdPartyEmotesToggle"
        static let clearLocalHistoryButton = "settings.clearLocalHistoryButton"
        static let deArrowToggle = "settings.deArrowToggle"
        static let disableAnalyticsToggle = "settings.disableAnalyticsToggle"
        static let forgetChannelSpeedsButton = "settings.forgetChannelSpeedsButton"
        static let glassStylePicker = "settings.glassStylePicker"
        static let gridColumnsLandscapePicker = "settings.gridColumnsLandscapePicker"
        static let gridColumnsPortraitPicker = "settings.gridColumnsPortraitPicker"
        static let hideLiveShortsToggle = "settings.hideLiveShortsToggle"
        static let hideShortsToggle = "settings.hideShortsToggle"
        static let hideVideoPremieresToggle = "settings.hideVideoPremieresToggle"
        static let watchedThresholdRow = "settings.watchedThresholdRow"
        static let hideWatchedInFeedsToggle = "settings.hideWatchedInFeedsToggle"
        static let skipWatchedToggle = "settings.skipWatchedToggle"
        static let watchedIncludesMusicToggle = "settings.watchedIncludesMusicToggle"
        static let watchedUsesYouTubeHistoryToggle = "settings.watchedUsesYouTubeHistoryToggle"
        static let iCloudSyncToggle = "settings.iCloudSyncToggle"
        static let perDeviceRecommendationsToggle = "settings.perDeviceRecommendationsToggle"
        static let prefer4KVP9Toggle = "settings.prefer4KVP9Toggle"
        static let preferH264Toggle = "settings.preferH264Toggle"
        static let preferredAudioLanguageRow = "settings.preferredAudioLanguageRow"
        static let preferredQualityPicker = "settings.preferredQualityPicker"
        static let removePINButton = "settings.removePINButton"
        static let resetAllButton = "settings.resetAllButton"
        static let seekBackRow = "settings.seekBackRow"
        static let seekForwardRow = "settings.seekForwardRow"
        static let sendDiagnosticReportButton = "settings.sendDiagnosticReportButton"
        static let setPINButton = "settings.setPINButton"
        static let showDislikesToggle = "settings.showDislikesToggle"
        static let showHomeHeroToggle = "settings.showHomeHeroToggle"
        static let signInButton = "settings.signInButton"
        static let sponsorBlockExcludedChannels = "settings.sponsorBlockExcludedChannels"
        static let sponsorBlockSegmentsLink = "settings.sponsorBlockSegmentsLink"
        static let sponsorBlockToggle = "settings.sponsorBlockToggle"
        static let themeRow = "settings.themeRow"
        static let thumbnailStylePicker = "settings.thumbnailStylePicker"
        static let useAsGuestButton = "settings.useAsGuestButton"
        static let useTOSPlayerOnMacToggle = "settings.useTOSPlayerOnMacToggle"
        static let visibleSectionsLink = "settings.visibleSectionsLink"
        static let watchHistoryToggle = "settings.watchHistoryToggle"
        static let whosWatchingLink = "settings.whosWatchingLink"

        /// A SponsorBlock category's action picker.
        static func sponsorBlockCategory(_ category: String) -> String { "settings.sponsorBlock.\(category)" }

        /// A profile's Show on Who's Watching toggle.
        static func whosWatchingProfile(_ profileId: String) -> String { "settings.whosWatching.\(profileId)" }
    }
}
