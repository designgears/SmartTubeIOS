import SmartTubeIOSCore
import SwiftUI

// MARK: - Playback

/// Speed, quality, audio language and what happens around playback.
struct PlaybackSettingsSection: View {
    @Environment(SettingsStore.self) private var store

    var body: some View {
        @Bindable var store = store
        Section("Playback") {
            TVPickerRow(
                "Default Playback Speed", value: Self.speedLabel(store.settings.playbackSpeed),
                choices: tvChoices($store.settings.playbackSpeed, AppSettings.availableSpeeds) { Self.speedLabel($0) }
            ) {
                Picker("Default Playback Speed", selection: $store.settings.playbackSpeed) {
                    ForEach(AppSettings.availableSpeeds, id: \.self) { speed in
                        Text(Self.speedLabel(speed)).tag(speed)
                    }
                }
            }
            if !store.settings.channelPlaybackSpeeds.isEmpty {
                // Speeds are remembered per channel when changed in the player (never for music).
                Button("Forget Channel Speeds (\(store.settings.channelPlaybackSpeeds.count))") {
                    store.settings.channelPlaybackSpeeds = [:]
                }
                .accessibilityIdentifier(AccessibilityID.Settings.forgetChannelSpeedsButton)
            }

            #if !os(iOS)
            TVPickerRow(
                "Default Quality", value: store.settings.preferredQuality.rawValue.capitalized,
                choices: tvChoices($store.settings.preferredQuality, AppSettings.VideoQuality.allCases) {
                    $0.rawValue.capitalized
                }
            ) {
                Picker("Default Quality", selection: $store.settings.preferredQuality) {
                    ForEach(AppSettings.VideoQuality.allCases, id: \.self) { quality in
                        Text(quality.rawValue.capitalized).tag(quality)
                    }
                }
                .accessibilityIdentifier(AccessibilityID.Settings.preferredQualityPicker)
            }
            if VideoCodecSupport.vp9HLS {
                // Only offered where VP9 is hardware-decoded (e.g. Apple TV 4K).
                Toggle("4K (VP9)", isOn: $store.settings.prefer4KVP9)
                    .accessibilityIdentifier(AccessibilityID.Settings.prefer4KVP9Toggle)
            }
            Toggle("Prefer H.264 Codec", isOn: $store.settings.preferH264)
                .accessibilityIdentifier(AccessibilityID.Settings.preferH264Toggle)
            TVPickerRow(
                "Audio Language", value: Self.audioLanguageLabel(store.settings.preferredAudioLanguage),
                choices: tvChoices($store.settings.preferredAudioLanguage, Self.audioLanguageCodes) {
                    Self.audioLanguageLabel($0)
                }
            ) {
                Picker("Audio Language", selection: $store.settings.preferredAudioLanguage) {
                    ForEach(Self.audioLanguageCodes, id: \.self) { code in
                        Text(Self.audioLanguageLabel(code)).tag(code)
                    }
                }
                .accessibilityIdentifier(AccessibilityID.Settings.preferredAudioLanguageRow)
            }
            TVPickerRow(
                "Video Fit", value: Self.fitLabel(store.settings.videoGravityMode),
                choices: tvChoices($store.settings.videoGravityMode, [.fit, .fill]) { Self.fitLabel($0) }
            ) {
                Picker("Video Fit", selection: $store.settings.videoGravityMode) {
                    ForEach([AppSettings.VideoGravityMode.fit, .fill], id: \.self) { mode in
                        Text(Self.fitLabel(mode)).tag(mode)
                    }
                }
            }
            #endif

            #if os(macOS)
            // tvOS and iOS use the player's own skip and controls behaviour.
            Stepper(
                "Seek Back: \(store.settings.seekBackSeconds) s", value: $store.settings.seekBackSeconds,
                in: 5...60, step: 5
            )
            .accessibilityIdentifier(AccessibilityID.Settings.seekBackRow)
            Stepper(
                "Seek Forward: \(store.settings.seekForwardSeconds) s", value: $store.settings.seekForwardSeconds,
                in: 5...60, step: 5
            )
            .accessibilityIdentifier(AccessibilityID.Settings.seekForwardRow)
            Picker("Hide Controls After", selection: $store.settings.controlsHideTimeout) {
                ForEach([2, 3, 4, 5, 8, 10], id: \.self) { Text("\($0)s").tag($0) }
            }
            #endif

            Toggle("Autoplay Next Video", isOn: $store.settings.autoplayEnabled)
            Toggle("Background Playback", isOn: $store.settings.backgroundPlaybackEnabled)
            Toggle("Loop Video", isOn: $store.settings.loopEnabled)
            Toggle("Shuffle", isOn: $store.settings.shuffleEnabled)
        }
    }

    // MARK: Labels

    /// Language codes offered by the audio language picker (nil = system default).
    static let audioLanguageCodes: [String?] = [
        nil, "en", "es", "fr", "de", "ja", "ko", "pt-BR", "zh-Hans", "original",
    ]

    static func speedLabel(_ speed: Double) -> String {
        speed == 1.0 ? "Normal" : "\(speed.formatted(.number.precision(.fractionLength(0...2))))×"
    }

    static func fitLabel(_ mode: AppSettings.VideoGravityMode) -> String {
        mode == .fill ? "Fill (crop)" : "Fit (letterbox)"
    }

    static func audioLanguageLabel(_ code: String?) -> String {
        switch code {
        case nil: return "System Default"
        case "original": return "Original Track Only"
        case "en": return "English"
        case "es": return "Spanish"
        case "fr": return "French"
        case "de": return "German"
        case "ja": return "Japanese"
        case "ko": return "Korean"
        case "pt-BR": return "Portuguese (Brazil)"
        case "zh-Hans": return "Chinese (Simplified)"
        case let other?: return Locale.current.localizedString(forIdentifier: other) ?? other
        }
    }
}
