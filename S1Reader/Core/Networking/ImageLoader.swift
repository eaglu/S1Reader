import SwiftUI
import UIKit

/// Loads remote images with the Referer header S1 requires for hot-link protection,
/// and keeps a decoded-image cache so scrolling stays smooth.
actor ImageLoader {
    static let shared = ImageLoader()

    private let cache = NSCache<NSURL, UIImage>()
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]

    init() {
        cache.countLimit = 200
    }

    func image(for url: URL) async -> UIImage? {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        if let task = inFlight[url] { return await task.value }

        let task = Task<UIImage?, Never> { [cache] in
            var request = URLRequest(url: url)
            request.setValue("https://stage1st.com/2b/", forHTTPHeaderField: "Referer")
            request.setValue(
                "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148",
                forHTTPHeaderField: "User-Agent"
            )
            request.timeoutInterval = 25
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let image = UIImage(data: data) else {
                return nil
            }
            cache.setObject(image, forKey: url as NSURL)
            return image
        }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil
        return image
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
