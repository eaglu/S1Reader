import SwiftUI
import UIKit
import ImageIO

/// Loads remote images with the Referer header S1 requires for hot-link protection.
///
/// Two cache layers:
/// - `NSCache` of decoded images, so scrolling back is instant
/// - disk-backed `URLCache` for the downloaded bytes, so images survive relaunches
///   and get revalidated with the ETag / max-age the hosts send
actor ImageLoader {
    static let shared = ImageLoader()

    /// Longest edge kept after downsampling; inline images never need more.
    private static let maxPixelSize: CGFloat = 1600
    private static let memoryCostLimit = 96 * 1024 * 1024

    private let cache: NSCache<NSURL, UIImage>
    private let session: URLSession
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]

    init() {
        let memory = NSCache<NSURL, UIImage>()
        memory.totalCostLimit = Self.memoryCostLimit
        cache = memory

        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(
            memoryCapacity: 32 * 1024 * 1024,
            diskCapacity: 300 * 1024 * 1024,
            diskPath: "s1-images"
        )
        configuration.requestCachePolicy = .useProtocolCachePolicy
        configuration.timeoutIntervalForRequest = 25
        configuration.httpAdditionalHeaders = [
            "Referer": "https://stage1st.com/2b/",
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148"
        ]
        session = URLSession(configuration: configuration)
    }

    func image(for url: URL) async -> UIImage? {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        if let task = inFlight[url] { return await task.value }

        let task = Task<UIImage?, Never> { [cache, session] in
            guard let (data, response) = try? await session.data(from: url),
                  let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let image = Self.downsampled(data) else {
                return nil
            }
            cache.setObject(image, forKey: url as NSURL, cost: Self.cost(of: image))
            return image
        }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil
        return image
    }

    /// Raw bytes at full resolution, for saving to the photo library.
    func originalData(for url: URL) async -> Data? {
        guard let (data, response) = try? await session.data(from: url),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            return nil
        }
        return data
    }

    /// Drops the given images from both cache layers, leaving other threads alone.
    func clearImages(for urls: [URL]) {
        for url in urls {
            cache.removeObject(forKey: url as NSURL)
            session.configuration.urlCache?.removeCachedResponse(for: URLRequest(url: url))
        }
    }

    /// Bytes currently held by the on-disk image cache.
    func diskUsage() -> Int {
        session.configuration.urlCache?.currentDiskUsage ?? 0
    }

    func clearCaches() {
        cache.removeAllObjects()
        session.configuration.urlCache?.removeAllCachedResponses()
    }

    /// Decodes and shrinks the image off the main thread so full-size screenshots
    /// in a long thread do not cost hundreds of megabytes of pixel memory.
    private static func downsampled(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return UIImage(data: data)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return UIImage(data: data)
        }
        return UIImage(cgImage: cgImage)
    }

    private static func cost(of image: UIImage) -> Int {
        guard let cgImage = image.cgImage else { return 1 }
        return cgImage.bytesPerRow * cgImage.height
    }
}

struct RemoteImage: View {
    let url: URL
    var contentMode: ContentMode = .fit

    @State private var image: UIImage?
    @State private var didFail = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if didFail {
                Image(systemName: "photo.badge.exclamationmark")
                    .font(.title3)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(.tertiarySystemFill))
                    .frame(height: 120)
                    .overlay(ProgressView())
            }
        }
        .task(id: url) {
            if image != nil { return }
            let loaded = await ImageLoader.shared.image(for: url)
            if loaded == nil { didFail = true } else { image = loaded }
        }
    }
}
