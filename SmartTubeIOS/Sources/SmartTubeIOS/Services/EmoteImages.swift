#if canImport(UIKit)
import Foundation
import ImageIO
import Observation
import UIKit

// MARK: - EmoteImages

/// Chat emote pictures, loaded once and kept: each is the first frame (animated emotes stand
/// still), scaled to the chat's line height. A message shows an emote's name until its picture
/// arrives, then redraws (the cache is observable).
@MainActor
@Observable
final class EmoteImages {
    static let shared = EmoteImages()

    /// Height on screen, in points.
    static let height: CGFloat = 40
    /// Pictures kept; the oldest go first.
    static let capacity = 600

    private var images: [URL: UIImage] = [:]
    @ObservationIgnored private var order: [URL] = []
    @ObservationIgnored private var loading: Set<URL> = []
    @ObservationIgnored private var failed: Set<URL> = []

    /// The picture if it's loaded; otherwise starts loading it and returns nil.
    func image(for url: URL) -> UIImage? {
        if let image = images[url] { return image }
        if !loading.contains(url), !failed.contains(url) { load(url) }
        return nil
    }

    private func load(_ url: URL) {
        loading.insert(url)
        let scale = UIScreen.main.scale
        Task { [weak self] in
            let image = await Self.decode(url, pixelHeight: Self.height * scale, scale: scale)
            guard let self else { return }
            self.loading.remove(url)
            guard let image else {
                self.failed.insert(url)
                return
            }
            self.images[url] = image
            self.order.append(url)
            if self.order.count > Self.capacity { self.images[self.order.removeFirst()] = nil }
        }
    }

    /// The first frame, at `pixelHeight` (kept in proportion).
    nonisolated private static func decode(_ url: URL, pixelHeight: CGFloat, scale: CGFloat) async -> UIImage? {
        guard let (data, response) = try? await URLSession.shared.data(from: url),
            (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? false,
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
            let height = properties[kCGImagePropertyPixelHeight] as? CGFloat, height > 0
        else { return nil }
        let longest = max(width, height) * pixelHeight / height
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: longest,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let frame = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: frame, scale: scale, orientation: .up)
    }
}
#endif
