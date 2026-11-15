#if os(tvOS)
import SmartTubeIOSCore
import SwiftUI

// MARK: - TVSettingsView

/// tvOS Settings-app layout: large artwork panel on the left, settings list on the right.
/// The list itself is the shared `SettingsView`, so every option keeps working.
struct TVSettingsView: View {
    @Environment(AuthService.self) private var auth

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 36) {
                Spacer()
                if auth.isSignedIn {
                    AsyncImage(url: auth.accountAvatarURL) { phase in
                        if case .success(let image) = phase {
                            image.resizable().scaledToFill()
                        } else {
                            Image(systemName: "person.crop.circle.fill")
                                .resizable().scaledToFit().foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 300, height: 300)
                    .clipShape(Circle())
                    Text(auth.accountName ?? "YouTube Account")
                        .font(.title2.weight(.bold))
                } else {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 280, weight: .light))
                        .foregroundStyle(.secondary)
                    Text("SmartTube").font(.title2.weight(.bold))
                }
                Text(appVersion).font(.headline).foregroundStyle(.secondary)
                Spacer()
            }
            .frame(width: 720)

            SettingsView()
                // Focused rows scale up past the list's bounds; without this the
                // enlarged pill's leading edge gets clipped.
                .scrollClipDisabled()
                .padding(.leading, 24)
                .padding(.trailing, TVLayout.pageInset)
                .frame(maxWidth: .infinity)
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
