#if os(iOS)
import SmartTubeIOSCore
import SwiftUI

// MARK: - GlassSettingsSection

/// Settings › Glass: how see-through the app's own panels are (see `appGlass`).
struct GlassSettingsSection: View {
    @Environment(SettingsStore.self) private var store

    var body: some View {
        @Bindable var store = store
        Section {
            Picker("Glass", selection: $store.settings.glassStyle) {
                ForEach(AppSettings.GlassStyle.allCases, id: \.self) { style in
                    Text(style.displayName).tag(style)
                }
            }
        } footer: {
            Text(
                "How see-through the player controls, mini player and other panels are. iOS draws the tab bar, "
                    + "navigation bars and menus itself; tone those down in iOS Settings › Display & Brightness › "
                    + "Liquid Glass, or Accessibility › Display & Text Size › Reduce Transparency.")
        }
    }
}
#endif
