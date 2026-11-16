#if os(tvOS)
import SmartTubeIOSCore
import SwiftUI

// MARK: - TVSettingsView

/// tvOS Settings: the profile (or the app) on the left, the shared `SettingsView` list on the
/// right — the same split every Settings sub-page uses (`settingsPage`).
struct TVSettingsView: View {
    @Environment(AuthService.self) private var auth

    var body: some View {
        TVSettingsLayout {
            if auth.isSignedIn {
                TVSettingsArtwork(symbol: AppSymbol.channel, imageURL: auth.accountAvatarURL)
            } else {
                TVSettingsArtwork(symbol: AppSymbol.settings)
            }
        } caption: {
            VStack(spacing: 12) {
                Text(auth.isSignedIn ? auth.accountName ?? "YouTube Account" : "SmartTube")
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                Text(appVersion).font(.headline).foregroundStyle(.secondary)
            }
        } content: {
            SettingsView()
        }
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Version \(version) (\(build))"
    }
}
#endif
