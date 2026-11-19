import SmartTubeIOSCore
import SwiftUI

// MARK: - Twitch & Kick

/// Ad blocking and live chat for Twitch and Kick.
struct StreamingSettingsSection: View {
    @Environment(SettingsStore.self) private var store

    var body: some View {
        @Bindable var store = store
        Section {
            Toggle("Block Twitch Ads", isOn: $store.settings.streaming.blockTwitchAds)
                .accessibilityIdentifier(AccessibilityID.Settings.blockTwitchAdsToggle)
            Toggle("Chat Emotes", isOn: $store.settings.streaming.chatEmotes)
                .accessibilityIdentifier(AccessibilityID.Settings.chatEmotesToggle)
            Toggle("7TV, BetterTTV & FFZ Emotes", isOn: $store.settings.streaming.thirdPartyEmotes)
                .accessibilityIdentifier(AccessibilityID.Settings.thirdPartyEmotesToggle)
                .disabled(!store.settings.streaming.chatEmotes)
        } header: {
            Text("Twitch & Kick")
        } footer: {
            Text(
                "Block Twitch Ads skips pre-rolls, and during an ad break plays Twitch's ad-free copy of the "
                    + "stream (360p at most) until the break ends. Kick always plays its ad-free stream. Chat "
                    + "Emotes shows emote pictures in live chat instead of their names; 7TV, BetterTTV and "
                    + "FrankerFaceZ add the channel's community emotes.")
        }
    }
}
