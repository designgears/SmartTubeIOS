#if !os(tvOS)
import SmartTubeIOSCore
import SwiftUI

// MARK: - Appearance

/// Theme, colour, thumbnails, layout and glass (tvOS has its own fixed look).
struct AppearanceSettingsSection: View {
    @Environment(SettingsStore.self) private var store

    private enum ThumbnailStyle: Hashable {
        case standard, highResolution, compact
    }

    var body: some View {
        @Bindable var store = store
        Section {
            Picker("Theme", selection: $store.settings.themeName) {
                ForEach(AppSettings.ThemeName.allCases, id: \.self) { theme in
                    Text(theme.rawValue).tag(theme)
                }
            }
            .accessibilityIdentifier(AccessibilityID.Settings.themeRow)
            Picker("Accent Color", selection: $store.settings.accentColor) {
                ForEach(AppSettings.AccentColorChoice.allCases, id: \.self) { choice in
                    Label {
                        Text(choice.displayName)
                    } icon: {
                        choice.swatch
                    }
                    .tag(choice)
                }
            }
            .accessibilityIdentifier(AccessibilityID.Settings.accentColorPicker)
            #if os(iOS)
            Picker("Glass", selection: $store.settings.glassStyle) {
                ForEach(AppSettings.GlassStyle.allCases, id: \.self) { style in
                    Text(style.displayName).tag(style)
                }
            }
            .accessibilityIdentifier(AccessibilityID.Settings.glassStylePicker)
            #endif
            Picker("Thumbnails", selection: thumbnailStyle) {
                Text("Standard").tag(ThumbnailStyle.standard)
                Text("High Resolution").tag(ThumbnailStyle.highResolution)
                Text("Compact").tag(ThumbnailStyle.compact)
            }
            .accessibilityIdentifier(AccessibilityID.Settings.thumbnailStylePicker)
            if !store.settings.compactThumbnails {
                Picker("Columns (Portrait)", selection: $store.settings.gridColumnsPortrait) {
                    ForEach(AppSettings.availableGridColumnCounts, id: \.self) { Text("\($0)").tag($0) }
                }
                .accessibilityIdentifier(AccessibilityID.Settings.gridColumnsPortraitPicker)
                Picker("Columns (Landscape)", selection: $store.settings.gridColumnsLandscape) {
                    ForEach(AppSettings.availableGridColumnCounts, id: \.self) { Text("\($0)").tag($0) }
                }
                .accessibilityIdentifier(AccessibilityID.Settings.gridColumnsLandscapePicker)
            }
            NavigationLink("Visible Sections") {
                SectionsSettingsView()
            }
            .accessibilityIdentifier(AccessibilityID.Settings.visibleSectionsLink)
        } header: {
            Text("Appearance")
        } footer: {
            #if os(iOS)
            Text(
                "Glass sets how see-through the player controls, mini player and other panels are. iOS draws its "
                    + "own bars and menus; tone those down in iOS Settings › Display & Brightness › Liquid Glass, "
                    + "or Accessibility › Display & Text Size › Reduce Transparency.")
            #endif
        }
    }

    /// One picker over the two independent `compactThumbnails` / `highResThumbnails` flags.
    private var thumbnailStyle: Binding<ThumbnailStyle> {
        Binding(
            get: {
                if store.settings.compactThumbnails { return .compact }
                return store.settings.highResThumbnails ? .highResolution : .standard
            },
            set: { style in
                store.settings.compactThumbnails = style == .compact
                store.settings.highResThumbnails = style == .highResolution
            }
        )
    }
}
#endif
