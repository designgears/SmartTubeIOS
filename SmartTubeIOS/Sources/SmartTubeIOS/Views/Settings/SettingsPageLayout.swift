import SmartTubeIOSCore
import SwiftUI

// MARK: - Settings page layout

extension View {
    /// A Settings page: on tvOS, artwork and a caption on the left and the list on the right,
    /// like the Settings app — the list never spans the whole screen. Elsewhere, unchanged.
    func settingsPage(symbol: String, caption: String? = nil) -> some View {
        modifier(SettingsPageModifier(symbol: symbol, imageURL: nil, caption: caption))
    }

    /// `settingsPage` with a picture (e.g. the current profile's avatar) instead of a symbol.
    func settingsPage(imageURL: URL?, fallbackSymbol: String, caption: String? = nil) -> some View {
        modifier(SettingsPageModifier(symbol: fallbackSymbol, imageURL: imageURL, caption: caption))
    }
}

private struct SettingsPageModifier: ViewModifier {
    let symbol: String
    let imageURL: URL?
    let caption: String?

    func body(content: Content) -> some View {
        #if os(tvOS)
        TVSettingsLayout {
            TVSettingsArtwork(symbol: symbol, imageURL: imageURL)
        } caption: {
            if let caption {
                Text(caption)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        } content: {
            content
        }
        #else
        content
        #endif
    }
}

#if os(tvOS)
/// The tvOS Settings split: a 720-point column of artwork and caption on the left, the list
/// on the right with the page inset.
struct TVSettingsLayout<Artwork: View, Caption: View, Content: View>: View {
    @ViewBuilder let artwork: () -> Artwork
    @ViewBuilder let caption: () -> Caption
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 36) {
                Spacer()
                artwork()
                caption()
                Spacer()
            }
            .padding(.horizontal, 60)
            .frame(width: 720)

            content()
                // Focused rows scale up past the list's bounds; without this the enlarged
                // pill's leading edge gets clipped.
                .scrollClipDisabled()
                .padding(.leading, 24)
                .padding(.trailing, TVLayout.pageInset)
                .frame(maxWidth: .infinity)
        }
    }
}

/// A large circular picture, or a symbol when there's no picture (or it fails to load).
struct TVSettingsArtwork: View {
    let symbol: String
    var imageURL: URL?

    var body: some View {
        if let imageURL {
            AsyncImage(url: imageURL) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    symbolView
                }
            }
            .frame(width: 300, height: 300)
            .clipShape(Circle())
        } else {
            symbolView
        }
    }

    private var symbolView: some View {
        Image(systemName: symbol)
            .font(.system(size: 200, weight: .light))
            .foregroundStyle(.secondary)
            .frame(width: 300, height: 300)
    }
}
#endif
