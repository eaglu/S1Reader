import SwiftUI
import UIKit

struct PostRowView: View {
    let post: Post
    var onImageTap: (URL) -> Void = { _ in }

    @State private var nodes: [PostNode] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if nodes.isEmpty && !post.message.isEmpty {
                Text(" ")
                    .redacted(reason: .placeholder)
            } else {
                PostContentView(nodes: nodes, onImageTap: onImageTap)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: post.pid) {
            let html = post.message
            nodes = await Task.detached(priority: .userInitiated) {
                HTMLParser.parse(html)
            }.value
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            AvatarView(uid: post.authorID, name: post.author, size: 24)

            Text(post.author)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)

            if post.isAdmin {
                Text("管理")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.orange.opacity(0.18), in: RoundedRectangle(cornerRadius: 3))
                    .foregroundStyle(.orange)
            }

            Spacer(minLength: 4)

            Text("#\(post.position)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)

            Text(Formatters.relative(post.dateline))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

struct PostContentView: View {
    let nodes: [PostNode]
    var onImageTap: (URL) -> Void = { _ in }

    @State private var smileys: [URL: UIImage] = [:]

    private enum Block {
        case text(Text)
        case image(URL)
    }

    private var blocks: [Block] {
        var result: [Block] = []
        var text = Text("")
        var hasText = false

        func flush() {
            guard hasText else { return }
            result.append(.text(text))
            text = Text("")
            hasText = false
        }

        for node in nodes {
            switch node {
            case .text(let attributed):
                text = text + Text(attributed)
                hasText = true
            case .image(let url, let isSmiley):
                if isSmiley {
                    if let image = smileys[url] {
                        text = text + Text(Image(uiImage: image))
                        hasText = true
                    }
                } else {
                    flush()
                    result.append(.image(url))
                }
            }
        }
        flush()
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .text(let text):
                    text
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                case .image(let url):
                    Button {
                        onImageTap(url)
                    } label: {
                        RemoteImage(url: url, contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: 460)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .task(id: nodes) {
            let urls = nodes.compactMap { node -> URL? in
                if case .image(let url, let isSmiley) = node, isSmiley { return url }
                return nil
            }
            for url in urls where smileys[url] == nil {
                if let image = await ImageLoader.shared.image(for: url) {
                    smileys[url] = Self.resized(image, height: 20)
                }
            }
        }
    }

    private static func resized(_ image: UIImage, height: CGFloat) -> UIImage {
        let ratio = image.size.width / max(image.size.height, 1)
        let size = CGSize(width: max(height * ratio, 4), height: height)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = UIScreen.main.scale
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
