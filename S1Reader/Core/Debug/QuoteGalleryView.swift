#if DEBUG
import SwiftUI

/// Debug-only gallery for the quoted block (`S1_OPEN=quotes`).
///
/// The live forum only ever shows one shape per thread, and a quote inside a
/// quote is rare enough that hunting one down is not a screenshot plan. This
/// screen draws every shape the card can take — plain, tappable, nested, header
/// only, long — in whatever appearance and text size the simulator is set to.
struct QuoteGalleryView: View {
    @Environment(\.dismiss) private var dismiss
    /// The thread parses at the reader's text size; the gallery has to do the
    /// same or it would show a card nobody sees.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The findpost link Discuz puts on a quote header; it is what makes the
    /// card tappable.
    private static let findpost = "forum.php?mod=redirect&amp;goto=findpost&amp;ptid=1&amp;pid="

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    sample("正文（对照组）", control)
                    sample("可点引用：正文和引用并排，箭头在头部右侧", tappable)
                    sample("无出处引用：没有头部，没有箭头", plain)
                    sample("嵌套引用：只缩进，不叠色", nested)
                    sample("长引用：换行不截断", long)
                }
                .padding()
            }
            .navigationTitle("引用样式")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    private func sample(_ title: String, _ html: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
            PostContentView(
                nodes: HTMLParser.parse(html, scale: HTMLParser.textScale(for: dynamicTypeSize)),
                onQuoteTap: { _ in },
                zoomNamespace: nil
            )
        }
    }

    private var control: String {
        "正文用的是正常字号：15pt 封顶。引用必须比它小一档，颜色也只淡一点。"
    }

    private var tappable: String {
        """
        上一行是正文，下面这块是引用。<br />
        <div class="reply_wrap"><a href="\(Self.findpost)111">C0s4qmLH9eF9P3w 发表于 2026-11-13 10:34</a>\
        <br />没想到 Hydrogen 能斩杀 1017，说好的量子退火呢。<br /></div>
        """
    }

    private var plain: String {
        "<div class=\"reply_wrap\">没有出处的引用，第一行就是正文，不需要箭头占位。<br /></div>"
    }

    private var nested: String {
        """
        <div class="reply_wrap"><a href="\(Self.findpost)222">甲 发表于 2026-11-12 09:00</a><br />外层引用\
        <blockquote>乙 发表于 2026-11-11 08:00<br />内层引用只缩进，不再铺一层灰。</blockquote>外层接着说。<br /></div>
        """
    }

    private var long: String {
        """
        <div class="reply_wrap"><a href="\(Self.findpost)333">丙 发表于 2026-11-10 07:00</a><br />\
        这是一段很长的引用，用来看换行和行距：引用区的正文按正文小一档排，行距跟正文一致，长段落只换行、\
        不截断，也不能压到卡片右边框外面去。再补一句把它撑到四行以上，方便看整块的高度。<br /></div>
        """
    }
}
#endif
