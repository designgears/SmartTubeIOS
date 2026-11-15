#if os(tvOS)
import ImageIO
import SmartTubeIOSCore
import SwiftUI
import UIKit

// MARK: - TVImagePipeline
//
// Thumbnail loading for the tvOS UI. Replaces AsyncImage, which has no memory cache
// (rows re-download and re-fade every time they scroll back in) and decodes full-size
// images on the main thread while rendering (scroll hitches, ~3.7 MB per 1280×720 thumb).
//
// - Downloads go through a URLSession with a disk URLCache.
// - Images are downsampled off the main thread with ImageIO to the pixel size they are
//   displayed at, and decoded up front (kCGImageSourceShouldCacheImmediately).
// - Decoded images live in a cost-limited NSCache, so revisited rows render instantly.
// - Concurrent requests for the same image share one download.

/// Decoded image wrapper so it can cross isolation domains (CGImage is immutable).
final class TVDecodedImage: @unchecked Sendable {
    let image: UIImage
    init(_ image: UIImage) { self.image = image }
}

enum TVImagePipeline {
    nonisolated(unsafe) private static let memory: NSCache<NSString, TVDecodedImage> = {
        let cache = NSCache<NSString, TVDecodedImage>()
        cache.totalCostLimit = 96 * 1024 * 1024  // decoded bytes
        cache.countLimit = 600
        return cache
    }()

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 16 * 1024 * 1024, diskCapacity: 256 * 1024 * 1024)
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.httpMaximumConnectionsPerHost = 6
        return URLSession(configuration: config)
    }()

    private static let loader = TVImageLoader()

    static func key(_ url: URL, _ maxPixel: Int) -> NSString {
        "\(url.absoluteString)#\(maxPixel)" as NSString
    }

    /// Synchronous cache hit (used to render without any placeholder when possible).
    static func cached(_ url: URL, maxPixel: Int) -> UIImage? {
        memory.object(forKey: key(url, maxPixel))?.image
    }

    /// Loads, downsamples and caches; returns nil on failure.
    static func image(_ url: URL, maxPixel: Int) async -> UIImage? {
        if let hit = cached(url, maxPixel: maxPixel) { return hit }
        guard let decoded = await loader.load(url, maxPixel: maxPixel, session: session) else { return nil }
        let image = decoded.image
        let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        memory.setObject(decoded, forKey: key(url, maxPixel), cost: cost)
        return image
    }

    /// Display scale (2 on a 4K TV, 1 at 1080p). Set once at launch by `TVRootView`.
    nonisolated(unsafe) static var screenScale: CGFloat = 2

    /// Pixel size for a view `points` wide on the current display.
    static func pixels(for points: CGFloat) -> Int {
        Int((points * screenScale).rounded())
    }

    /// Best-effort background warm-up (e.g. the next cards in a row).
    static func prefetch(_ urls: [URL], maxPixel: Int) {
        for url in urls where cached(url, maxPixel: maxPixel) == nil {
            Task(priority: .utility) { _ = await image(url, maxPixel: maxPixel) }
        }
    }

    /// Warms the thumbnails of the cards just past `index` (a grid row or two ahead).
    static func prefetchThumbnails(_ videos: [Video], after index: Int, pointWidth: CGFloat, count: Int = 8) {
        let upcoming = videos.dropFirst(index + 1).prefix(count)
        prefetch(upcoming.compactMap { TVVideoThumbnail.urls(for: $0).first }, maxPixel: pixels(for: pointWidth))
    }

    nonisolated static func downsample(_ data: Data, maxPixel: Int) -> TVDecodedImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options =
            [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceShouldCacheImmediately: true,  // decode now, off the main thread
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return TVDecodedImage(UIImage(cgImage: cgImage))
    }
}

/// De-duplicates concurrent downloads of the same image.
private actor TVImageLoader {
    private var inFlight: [NSString: Task<TVDecodedImage?, Never>] = [:]

    func load(_ url: URL, maxPixel: Int, session: URLSession) async -> TVDecodedImage? {
        let key = TVImagePipeline.key(url, maxPixel)
        if let task = inFlight[key] { return await task.value }
        let task = Task.detached(priority: .userInitiated) { () -> TVDecodedImage? in
            guard let (data, response) = try? await session.data(from: url),
                let http = response as? HTTPURLResponse, http.statusCode == 200
            else { return nil }
            return TVImagePipeline.downsample(data, maxPixel: maxPixel)
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        return result
    }
}

// MARK: - TVRemoteImage

/// Fills its frame with the first URL in `urls` that loads (later ones are fallbacks),
/// downsampled to `pointWidth` on screen. Cached images render immediately (no fade).
struct TVRemoteImage: View {
    let urls: [URL]
    let pointWidth: CGFloat
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?

    init(urls: [URL], pointWidth: CGFloat, contentMode: ContentMode = .fill) {
        self.urls = urls
        self.pointWidth = pointWidth
        self.contentMode = contentMode
        let maxPixel = TVImagePipeline.pixels(for: pointWidth)
        _image = State(initialValue: urls.first.flatMap { TVImagePipeline.cached($0, maxPixel: maxPixel) })
    }

    var body: some View {
        // The placeholder defines the layout size; the image is an overlay so a `.fill`
        // image can never grow the view beyond the frame it was proposed.
        Color.white.opacity(0.06)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                        .transition(.opacity)
                }
            }
            .clipped()
            .task(id: urls.first) {
                guard image == nil else { return }
                let maxPixel = TVImagePipeline.pixels(for: pointWidth)
                for url in urls {
                    if let loaded = await TVImagePipeline.image(url, maxPixel: maxPixel) {
                        withAnimation(.easeOut(duration: 0.18)) { image = loaded }
                        return
                    }
                }
            }
    }
}
#endif
