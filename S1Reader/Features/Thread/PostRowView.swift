import SwiftUI
import UIKit

struct PostRowView: View {
    let post: Post
    var onImageTap: (URL) -> Void = { _ in }

    @State private var nodes: [PostNode] = []
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if nodes.isEmpty && !post.message.isEmpty {
                Text(" ")
                    .redacted(reason: .placeholder)
            } else {
                PostContentView(nodes: nodes, onImageTap: onImageTap)
                    .contextMenu { menu }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Re-parse when the reader changes the system text size so the body
        // follows Dynamic Type instead of staying at Discuz's fixed sizes.
        .task(id: "\(post.pid)-\(dynamicTypeSize)") {
            let html = post.message
            let scale = HTMLParser.textScale(for: dynamicTypeSize)
            nodes = await Task.detached(priority: .userInitiated) {
                HTMLParser.parse(html, scale: scale)
            }.value
        }
    }

    /// Floor link, shareable from the context menu.
    private var floorURL: URL? {
        URL(string: "https://stage1st.com/2b/forum.php?mod=redirect&goto=findpost&ptid=\(post.tid)&pid=\(post.pid)")
    }

    @ViewBuilder
    private var menu: some View {
        Button {
            UIPasteboard.general.string = HTMLParser.plainText(post.message)
        } label: {
            Label("复制文字", systemImage: "doc.on.doc")
        }
        if let floorURL {
            Button {
                UIPasteboard.general.url = floorURL
            } label: {
                Label("复制链接", systemImage: "link")
            }
            ShareLink(item: floorURL) {
                Label("分享本楼", systemImage: "square.and.arrow.up")
            }
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
    @State private var saveMessage: String?
    @State private var needsPhotoPermission = false
    @State private var savedSuccessfully = 0

    private enum Block {
        case text(Text)
        case quote(AttributedString)
        case image(URL)
    }

    private var blocks: [Block] {
        var result: [Block] = []
        var pieces: [Text] = []

        func flush() {
            guard !pieces.isEmpty else { return }
            result.append(.text(pieces.reduce(Text(""), +)))
            pieces.removeAll()
        }

        for node in nodes {
            switch node {
            case .text(let attributed):
                pieces.append(Text(attributed))
            case .image(let url, let isSmiley):
                if isSmiley {
                    if let image = smileys[url] {
                        pieces.append(Text(Image(uiImage: image)))
                    }
                } else {
                    flush()
                    result.append(.image(url))
                }
            case .quote(let attributed):
                flush()
                result.append(.quote(attributed))
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
                case .quote(let attributed):
                    Text(attributed)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                        .padding(.leading, 12)
                        .padding(.trailing, 10)
                        .background(
                            Color(uiColor: .tertiarySystemFill),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                        .overlay(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                .fill(Color.accentColor.opacity(0.5))
                                .frame(width: 3)
                                .padding(.vertical, 6)
                        }
                case .image(let url):
                    Button {
                        onImageTap(url)
                    } label: {
                        RemoteImage(url: url, contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: 460)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("帖子图片")
                    .accessibilityHint("双击查看大图")
                    .contextMenu {
                        Button {
                            save(url)
                        } label: {
                            Label("保存到相册", systemImage: "square.and.arrow.down")
                        }
                        ShareLink(item: url) {
                            Label("分享图片", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
        }
        .alert(saveMessage ?? "", isPresented: Binding(
            get: { saveMessage != nil },
            set: { if !$0 { saveMessage = nil } }
        )) {
            Button("好", role: .cancel) { saveMessage = nil }
        }
        .sensoryFeedback(.success, trigger: savedSuccessfully)
        .task(id: nodes) {
            let urls = nodes.compactMap { node -> URL? in
                if case .image(let url, let isSmiley) = node, isSmiley { return url }
                return nil
            }
            for url in urls where smileys[url] == nil {
                // Bundled set first, so the common smileys never hit the network.
                if let local = Self.smiley(for: url) {
                    smileys[url] = local
                } else if let image = await ImageLoader.shared.image(for: url) {
                    let resized = Self.resized(image, height: Self.smileyHeight)
                    Self.resizedCache.setObject(resized, forKey: url as NSURL)
                    smileys[url] = resized
                }
            }
        }
    }

    private func save(_ url: URL) {
        Task {
            do {
                try await ImageSaver.save(url)
                needsPhotoPermission = false
                savedSuccessfully += 1
                saveMessage = "已保存到相册"
            } catch {
                needsPhotoPermission = (error as? ImageSaveError) == .denied
                saveMessage = error.localizedDescription
            }
        }
    }

    private static let smileyHeight: CGFloat = 20
    private static let resizedCache = NSCache<NSURL, UIImage>()

    /// Bundled smiley, resized once per URL and kept so scrolling back is free.
    private static func smiley(for url: URL) -> UIImage? {
        if let cached = resizedCache.object(forKey: url as NSURL) { return cached }
        guard let bundled = Smileys.bundled(url) else { return nil }
        let resized = Self.resized(bundled, height: smileyHeight)
        resizedCache.setObject(resized, forKey: url as NSURL)
        return resized
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
