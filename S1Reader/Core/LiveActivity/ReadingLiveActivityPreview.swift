#if DEBUG
import ActivityKit
import SwiftUI

/// `S1_OPEN=liveactivity` puts the Lock Screen card on screen by itself.
///
/// The simulator screenshots the Lock Screen poorly (and there is no command
/// line way to lock it), so the card is checked here: it is the same
/// `ReadingLockScreenView` the widget extension draws, with a sample thread.
///
/// `S1_LIVEACTIVITY=demo` starts a real activity with the same sample thread,
/// so the island can be looked at; `demo-pair` starts a second one, which is
/// the only way the system squeezes one of them into the minimal form.
struct ReadingLiveActivityPreview: View {
    private static let sample = ReadingActivityAttributes.ContentState(
        title: "有生之年还能看到续作吗",
        page: 398,
        pageCount: 483,
        author: "eaglu",
        excerpt: "最近重看了一遍，还是觉得这一段的节奏最好，可惜后面收得太急。"
    )

    var body: some View {
        ReadingLockScreenView(
            title: Self.sample.title,
            pageLabel: Self.sample.pageLabel,
            author: Self.sample.author,
            excerpt: Self.sample.excerpt,
            progress: Self.sample.progress
        )
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(.systemGroupedBackground))
        .task {
            let mode = DebugHooks.string("S1_LIVEACTIVITY")
            guard mode == "demo" || mode == "demo-pair" else { return }
            await ReadingLiveActivity.endAll()
            await ReadingLiveActivity.present(tid: "preview", state: Self.sample)
            guard mode == "demo-pair" else { return }
            _ = try? Activity.request(
                attributes: ReadingActivityAttributes(tid: "preview-minimal"),
                content: ActivityContent(state: Self.sample, staleDate: nil),
                pushType: nil
            )
        }
    }
}
#endif
