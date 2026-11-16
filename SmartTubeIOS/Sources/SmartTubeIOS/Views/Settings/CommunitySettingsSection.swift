import SmartTubeIOSCore
import SwiftUI

// MARK: - Community

/// Community-run services: SponsorBlock, DeArrow, Return YouTube Dislike.
struct CommunitySettingsSection: View {
    @Environment(SettingsStore.self) private var store

    var body: some View {
        @Bindable var store = store
        Section {
            Toggle("SponsorBlock", isOn: $store.settings.sponsorBlockEnabled)
                .accessibilityIdentifier(AccessibilityID.Settings.sponsorBlockToggle)
            if store.settings.sponsorBlockEnabled {
                NavigationLink("SponsorBlock Segments") {
                    SponsorBlockSettingsView()
                }
                .accessibilityIdentifier(AccessibilityID.Settings.sponsorBlockSegmentsLink)
            }
            Toggle("DeArrow", isOn: $store.settings.deArrowEnabled)
                .accessibilityIdentifier(AccessibilityID.Settings.deArrowToggle)
            Toggle("Show Dislikes", isOn: $store.settings.showDislikes)
                .accessibilityIdentifier(AccessibilityID.Settings.showDislikesToggle)
        } header: {
            Text("Community")
        } footer: {
            Text(
                "SponsorBlock skips sponsors and other segments viewers mark. DeArrow replaces clickbait titles and "
                    + "thumbnails. Dislikes are estimated by Return YouTube Dislike. Each sends the video's ID to "
                    + "its service.")
        }
    }
}

// MARK: - SponsorBlock page

/// Settings › SponsorBlock Segments: what to do with each kind of segment.
struct SponsorBlockSettingsView: View {
    @Environment(SettingsStore.self) private var store

    var body: some View {
        @Bindable var store = store
        Form {
            Section {
                ForEach(SponsorSegment.Category.allCases, id: \.self) { category in
                    categoryRow(category)
                }
            } footer: {
                Text("Skip jumps past the segment, Show Skip Button lets you choose, Nothing plays it through.")
            }
            Section {
                TVPickerRow(
                    "Ignore Segments Shorter Than",
                    value: Self.segmentLengthLabel(store.settings.sponsorBlockMinSegmentDuration),
                    choices: tvChoices($store.settings.sponsorBlockMinSegmentDuration, Self.segmentLengths) {
                        Self.segmentLengthLabel($0)
                    }
                ) {
                    Picker("Ignore Segments Shorter Than", selection: $store.settings.sponsorBlockMinSegmentDuration) {
                        ForEach(Self.segmentLengths, id: \.self) { Text(Self.segmentLengthLabel($0)).tag($0) }
                    }
                }
                NavigationLink {
                    SponsorBlockExcludedChannelsView()
                } label: {
                    LabeledContent(
                        "Excluded Channels", value: "\(store.settings.sponsorBlockExcludedChannels.count)")
                }
                .accessibilityIdentifier(AccessibilityID.Settings.sponsorBlockExcludedChannels)
            }
        }
        .navigationTitle("SponsorBlock")
        #if os(tvOS)
        .pickerStyle(.menu)
        #endif
        #if os(iOS)
        .toolbar(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func categoryRow(_ category: SponsorSegment.Category) -> some View {
        let action = Binding(
            get: { store.settings.sponsorBlockActions[category] ?? .nothing },
            set: { store.settings.sponsorBlockActions[category] = $0 }
        )
        return TVPickerRow(
            category.displayName, value: Self.actionLabel(action.wrappedValue), dot: category.color,
            choices: tvChoices(action, AppSettings.SponsorBlockAction.allCases) { Self.actionLabel($0) }
        ) {
            Picker(selection: action) {
                ForEach(AppSettings.SponsorBlockAction.allCases, id: \.self) { Text(Self.actionLabel($0)).tag($0) }
            } label: {
                Label {
                    Text(category.displayName)
                } icon: {
                    Circle().fill(category.color).frame(width: 10, height: 10)
                }
            }
            .accessibilityIdentifier(AccessibilityID.Settings.sponsorBlockCategory(category.rawValue))
        }
    }

    private static let segmentLengths: [Double] = [0, 1, 2, 5, 10]

    static func segmentLengthLabel(_ seconds: Double) -> String {
        seconds == 0 ? "Off" : "\(Int(seconds))s"
    }

    static func actionLabel(_ action: AppSettings.SponsorBlockAction) -> String {
        switch action {
        case .skip: return "Skip"
        case .showToast: return "Show Skip Button"
        case .nothing: return "Nothing"
        }
    }
}

// MARK: - SponsorBlockExcludedChannelsView

/// Lists channels excluded from SponsorBlock processing.
/// Channels can be added from ChannelView and removed here via swipe-to-delete.
struct SponsorBlockExcludedChannelsView: View {
    @Environment(SettingsStore.self) private var store

    var body: some View {
        @Bindable var store = store
        let sortedChannels = store.settings.sponsorBlockExcludedChannels
            .sorted { $0.value.localizedCompare($1.value) == .orderedAscending }
        return List {
            if sortedChannels.isEmpty {
                ContentUnavailableView(
                    "No Excluded Channels",
                    systemImage: "person.crop.circle.badge.minus",
                    description: Text(
                        "Open a channel and tap \u{201C}Exclude from SponsorBlock\u{201D} to add it here.")
                )
                #if os(tvOS)
                // Something must take focus or the page traps the Siri Remote.
                .focusable()
                #endif
            } else {
                ForEach(sortedChannels, id: \.key) { channelId, title in
                    #if os(tvOS)
                    // tvOS has no swipe-to-delete: rows are buttons that remove the channel.
                    Button {
                        store.settings.sponsorBlockExcludedChannels.removeValue(forKey: channelId)
                    } label: {
                        HStack {
                            Text(title)
                            Spacer()
                            Text("Remove").foregroundStyle(.secondary)
                        }
                    }
                    #else
                    Text(title)
                    #endif
                }
                .onDelete { indices in
                    let ids = indices.map { sortedChannels[$0].key }
                    ids.forEach { store.settings.sponsorBlockExcludedChannels.removeValue(forKey: $0) }
                }
            }
        }
        .navigationTitle("Excluded Channels")
        #if os(iOS)
        .toolbar(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            EditButton()
        }
        #endif
    }
}
