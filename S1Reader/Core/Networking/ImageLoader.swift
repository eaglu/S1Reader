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
    private var probingAspects: Set<URL> = []
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

    /// Asks for just the first bytes of a picture to learn its aspect ratio.
    ///
    /// The body is downloaded lazily by `image(for:)` once the row is on screen;
    /// this early peek exists only so the placeholder can reserve the exact
    /// height and the list stops jumping when the picture lands.
    func aspectRatio(for url: URL) async -> CGFloat? {
        if let known = await ImageAspectStore.shared.aspect(for: url) { return known }
        if probingAspects.contains(url) { return nil }
        probingAspects.insert(url)
        defer { probingAspects.remove(url) }

        var request = URLRequest(url: url)
        request.setValue("bytes=0-65535", forHTTPHeaderField: "Range")

        guard let (data, _) = try? await session.data(for: request), !data.isEmpty,
              let aspect = Self.aspectRatio(from: data) else { return nil }
        #if DEBUG
        print("S1 image probe \(url.lastPathComponent) aspect=\(String(format: "%.3f", aspect)) bytes=\(data.count)")
        #endif
        await ImageAspectStore.shared.store(aspect: aspect, for: url)
        return aspect
    }

    /// Reads the pixel size straight out of the (partial) image bytes.
    private static func aspectRatio(from data: Data) -> CGFloat? {
        guard let source = CGImageSourceCreateIncremental(nil as CFDictionary?) as CGImageSource? else { return nil }
        CGImageSourceUpdateData(source, data as CFData, false)
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              width > 0, height > 0 else { return nil }
        return CGFloat(width / height)
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
    /// Lets a caller that already knows the picture is on screen start at once
    /// (the full-screen viewer), instead of waiting for the scroll signal.
    var startsLoadingImmediately = false
    /// Upper bound so a very tall picture cannot swallow the whole screen.
    var maxHeight: CGFloat = 460

    @State private var image: UIImage?
    @State private var didFail = false
    @State private var isOnScreen = false
    @State private var aspect: CGFloat?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                placeholder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: image == nil ? maxHeight : nil)
        // Pictures arrive at different moments; a short fade keeps them from
        // popping in mid-scroll.
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: image == nil)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: didFail)
        // Reserved space follows the real ratio once the peek answers, so the
        // list settles instead of snapping when the picture lands.
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: aspect)
        .visibleInScroll { visible in
            isOnScreen = visible
            if visible { load() }
        }
        .task(id: url.absoluteString) {
            if aspect == nil { aspect = await ImageAspectStore.shared.aspect(for: url) }
        }
        .onChange(of: url) {
            image = nil
            didFail = false
            aspect = nil
            load()
        }
        .onAppear {
            if startsLoadingImmediately { load() }
        }
    }

    /// Same footprint the picture will occupy: known ratio if we have it, a
    /// plain grey card at a sensible ratio until the peek answers.
    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color(uiColor: .tertiarySystemFill))
            .aspectRatio(aspect ?? 4.0 / 3.0, contentMode: .fit)
            .overlay(ProgressView())
    }

    /// Fetches only once the picture is actually on screen; pictures that were
    /// merely built ahead of the viewport stay as placeholders until scrolled to.
    private func load() {
        guard image == nil, !didFail else { return }
        guard isOnScreen || startsLoadingImmediately else {
            #if DEBUG
            print("S1 image deferred \(url.lastPathComponent)")
            #endif
            return
        }
        #if DEBUG
        print("S1 image start \(url.lastPathComponent)")
        #endif
        // Learn the size first: it is a few kilobytes and keeps the row from
        // resizing once the body shows up.
        if aspect == nil {
            Task {
                if let probed = await ImageLoader.shared.aspectRatio(for: url) {
                    aspect = probed
                }
            }
        }
        Task {
            let loaded = await ImageLoader.shared.image(for: url)
            if let loaded {
                image = loaded
                if aspect == nil, loaded.size.height > 0 {
                    aspect = loaded.size.width / loaded.size.height
                }
                await ImageAspectStore.shared.store(
                    aspect: loaded.size.width / max(1, loaded.size.height),
                    for: url
                )
            } else {
                didFail = true
            }
        }
    }
}
