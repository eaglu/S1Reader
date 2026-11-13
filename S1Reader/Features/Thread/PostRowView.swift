import SwiftUI
import UIKit

struct PostRowView: View {
    let post: Post
    var onImageTap: (URL) -> Void = { _ in }
    var onQuoteTap: (String) -> Void = { _ in }
    /// Opens the author's profile sheet.
    var onAuthorTap: ((Post) -> Void)?
    /// Adds/removes the author from the local block list.
    var onBlockAuthor: ((Post) -> Void)?
    var isAuthorBlocked = false
    /// Shared with the full-screen viewer so a tapped picture can grow out of
    /// its thumbnail (iOS 18 and later).
    var zoomNamespace: Namespace.ID?

    @State private var nodes: [PostNode] = []
    /// True once this row has parsed the body itself (cache hit or fresh parse),
    /// so "no nodes" can be told apart from "not parsed yet".
    @State private var didParse = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The body to draw. A row that `LazyVStack` just rebuilt has empty `@State`,
    /// so it reads the parsed body straight out of the mirror instead of waiting
    /// a frame for the actor: a row above the viewport that starts out one line
    /// tall and then grows shoves the reply being read down the screen.
    private var shownNodes: [PostNode] {
        if didParse { return nodes }
        return PostNodeMirror.shared.nodes(
            pid: post.pid,
            scale: HTMLParser.textScale(for: dynamicTypeSize)
        ) ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if shownNodes.isEmpty && !post.message.isEmpty {
                Text(" ")
                    .redacted(reason: .placeholder)
                    .accessibilityIdentifier("postPlaceholder-\(post.pid)")
            } else {
                PostContentView(
                    nodes: shownNodes,
                    onImageTap: onImageTap,
                    onQuoteTap: onQuoteTap,
                    zoomNamespace: zoomNamespace
                )
                    // The UI test looks for this to prove a floor rendered text and
                    // not the grey placeholder bar.
                    .accessibilityIdentifier("postBody-\(post.pid)")
                    .contextMenu { menu }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Re-parse when the reader changes the system text size so the body
        // follows Dynamic Type instead of staying at Discuz's fixed sizes.
        .task(id: "\(post.pid)-\(dynamicTypeSize)") {
            let parsed = await PostBodyCache.shared.nodes(
                pid: post.pid,
                html: post.message,
                scale: HTMLParser.textScale(for: dynamicTypeSize)
            )
            // Always fill `nodes` itself: once `didParse` flips, the body stops
            // reading the mirror, and a mirror hit that skipped this assignment
            // would leave the row blank. Assigning the same body again is a no-op
            // for layout, so the row is still not laid out twice.
            if nodes != parsed { nodes = parsed }
            didParse = true
        }
    }

    /// Floor link, shareable from the context menu.
    private var floorURL: URL? {
        URL(string: "https://stage1st.com/2b/forum.php?mod=redirect&goto=findpost&ptid=\(post.tid)&pid=\(post.pid)")
    }

    @ViewBuilder
    private var menu: some View {
        if let onAuthorTap {
            Button {
                onAuthorTap(post)
            } label: {
                Label("作者资料", systemImage: "person.crop.circle")
            }
        }
        if let onBlockAuthor, !post.authorID.isEmpty, post.authorID != "0" {
            Button {
                onBlockAuthor(post)
            } label: {
                Label(
                    isAuthorBlocked ? "取消屏蔽此作者" : "屏蔽此作者",
                    systemImage: isAuthorBlocked ? "person.badge.plus" : "person.slash"
                )
            }
        }
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
        let who = HStack(spacing: 8) {
            if let onAuthorTap {
                Button { onAuthorTap(post) } label: {
                    HStack(spacing: 8) {
                        AvatarView(uid: post.authorID, name: post.author, size: 24)

                        Text(post.author)
                            .font(.subheadline.weight(.semibold))
                            .lineLimitForAccessibility(1)
                    }
                    // 44pt target around a 24pt avatar, without a taller row.
                    .contentShape(Rectangle().inset(by: -10))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("查看 \(post.author) 的资料")
            } else {
                AvatarView(uid: post.authorID, name: post.author, size: 24)

                Text(post.author)
                    .font(.subheadline.weight(.semibold))
                    .lineLimitForAccessibility(1)
            }

            if post.isAdmin { adminBadge }
        }

        let when = HStack(spacing: 8) {
            Text("#\(post.position)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)

            Text(Formatters.relative(post.dateline))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }

        // At accessibility sizes the name and the metadata each need a line of
        // their own; side by side they squeeze the author into "活…".
        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    who
                    when
                }
            } else {
                HStack(spacing: 8) {
                    who
                    Spacer(minLength: 4)
                    when
                }
            }
        }
    }

    private var adminBadge: some View {
        Text("管理")
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Color.orange.opacity(0.18), in: RoundedRectangle(cornerRadius: 3))
            .foregroundStyle(.orange)
    }
}

struct PostContentView: View {
    let nodes: [PostNode]
    var onImageTap: (URL) -> Void = { _ in }
    var onQuoteTap: (String) -> Void = { _ in }
    var zoomNamespace: Namespace.ID?

    @State private var smileys: [URL: UIImage] = [:]
    @State private var saveMessage: String?
    @State private var needsPhotoPermission = false
    @State private var savedSuccessfully = 0

    private enum Block {
        case text(Text)
        case quote(PostNode.Quote)
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
                    // Bundled smileys resolve synchronously, so a rebuilt row lays
                    // its text out at the final line count on the first pass. Only
                    // a smiley this build does not carry arrives a frame later.
                    if let image = smileys[url] ?? Self.smiley(for: url) {
                        pieces.append(Text(Image(uiImage: image)))
                    }
                } else {
                    flush()
                    result.append(.image(url))
                }
            case .quote(let quote):
                flush()
                result.append(.quote(quote))
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
                case .quote(let quote):
                    QuoteCard(quote: quote, onQuoteTap: onQuoteTap)
                case .image(let url):
                    Button {
                        onImageTap(url)
                    } label: {
                        RemoteImage(url: url, contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: 460)
                    }
                    .buttonStyle(.plain)
                    .zoomSource(id: url.absoluteString, in: zoomNamespace)
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

/// One quoted block: a caption row with the original author and time, a hairline,
/// then the quoted body one size step below the reply.
///
/// A tappable quote marks itself with a turnaround glyph on the caption row
/// rather than a coloured spine, and keeps the press feedback, so it reads as a
/// control without shouting over the reply it sits in.
private struct QuoteCard: View {
    let quote: PostNode.Quote
    /// 1 for a quote in the reply itself; nested cards are indented and untinted.
    var depth = 1
    var onQuoteTap: (String) -> Void = { _ in }
    /// Nested cards are drawn inside their parent's button, where a button of
    /// their own would never receive the tap; they are display-only.
    var interactive = true

    private var isControl: Bool { interactive && quote.pid != nil }
    private var isNested: Bool { depth > 1 }

    var body: some View {
        if let pid = quote.pid, isControl {
            Button {
                onQuoteTap(pid)
            } label: {
                card
            }
            .buttonStyle(QuoteCardButtonStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("引用的回复")
            .accessibilityHint("双击跳到被引用的楼层")
            .accessibilityAddTraits(.isButton)
        } else {
            card.textSelection(.enabled)
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let header = quote.header {
                headerRow(header)
                Rectangle()
                    .fill(QuoteStyle.hairline)
                    .frame(height: 0.5)
                    .padding(.top, 6)
            }

            HStack(alignment: .top, spacing: 8) {
                QuoteBody(quote: quote, depth: depth, onQuoteTap: onQuoteTap)
                // Without a caption row the glyph has nowhere else to go.
                if quote.header == nil, isControl { affordance }
            }
            .padding(.top, quote.header == nil ? 0 : 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background {
            if !isNested {
                RoundedRectangle(cornerRadius: QuoteStyle.cornerRadius, style: .continuous)
                    .fill(QuoteStyle.fill)
            }
        }
        .padding(.leading, isNested ? QuoteStyle.nestIndent : 0)
        .contentShape(RoundedRectangle(cornerRadius: QuoteStyle.cornerRadius, style: .continuous))
    }

    private func headerRow(_ header: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(header)
                .font(.caption2)
                .foregroundStyle(QuoteStyle.header)
                .fixedSize(horizontal: false, vertical: true)
            if isControl {
                Spacer(minLength: 4)
                affordance
            }
        }
    }

    private var affordance: some View {
        Image(systemName: QuoteStyle.affordanceSymbol)
            .font(.system(size: QuoteStyle.affordanceSize, weight: .semibold))
            .foregroundStyle(QuoteStyle.header)
            .accessibilityHidden(true)
    }
}

/// The quoted text and any quote nested inside it. Consecutive text runs are
/// folded into one `Text` so a smiley or a line break cannot split a sentence
/// into separate paragraphs.
private struct QuoteBody: View {
    let quote: PostNode.Quote
    let depth: Int
    var onQuoteTap: (String) -> Void = { _ in }

    private enum Segment {
        case text(Text)
        case quote(PostNode.Quote)
    }

    private var segments: [Segment] {
        var result: [Segment] = []
        var pieces: [Text] = []

        func flush() {
            guard !pieces.isEmpty else { return }
            result.append(.text(pieces.reduce(Text(""), +)))
            pieces.removeAll()
        }

        for node in quote.body {
            switch node {
            case .text(let attributed):
                pieces.append(Text(attributed))
            case .quote(let nested):
                flush()
                result.append(.quote(nested))
            case .image:
                // The parser drops images inside quotes; the original picture is
                // one tap away.
                continue
            }
        }
        flush()
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .text(let text):
                    text
                        .foregroundStyle(QuoteStyle.body)
                        .fixedSize(horizontal: false, vertical: true)
                case .quote(let nested):
                    QuoteCard(
                        quote: nested,
                        depth: depth + 1,
                        onQuoteTap: onQuoteTap,
                        interactive: false
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct QuoteCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay {
                RoundedRectangle(cornerRadius: QuoteStyle.cornerRadius, style: .continuous)
                    .fill(configuration.isPressed ? Color.primary.opacity(0.06) : Color.clear)
            }
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

