import SmartTubeIOSCore
import SwiftUI

// MARK: - Colors

/// The color of the watched bar drawn over videos (LIVE badges use each service's own color).
struct ColorSettingsSection: View {
    @Environment(SettingsStore.self) private var store

    /// Every named color; "Default" means nothing for these marks.
    private static let choices = AppSettings.AccentColorChoice.allCases.filter { $0 != .system }

    var body: some View {
        @Bindable var store = store
        Section {
            row("Watched Bar", $store.settings.watchedBarColor)
                .accessibilityIdentifier(AccessibilityID.Settings.watchedBarColorPicker)
        } header: {
            Text("Colors")
        } footer: {
            Text("Watched Bar is the bar under a video showing how much you've seen.")
        }
    }

    private func row(_ label: String, _ selection: Binding<AppSettings.AccentColorChoice>) -> some View {
        TVPickerRow(
            label, value: selection.wrappedValue.displayName, dot: selection.wrappedValue.color,
            choices: tvChoices(selection, Self.choices) { $0.displayName }
        ) {
            Picker(label, selection: selection) {
                ForEach(Self.choices, id: \.self) { choice in
                    Label {
                        Text(choice.displayName)
                    } icon: {
                        choice.swatch
                    }
                    .tag(choice)
                }
            }
        }
    }
}
