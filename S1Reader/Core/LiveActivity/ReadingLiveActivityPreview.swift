#if DEBUG
import SwiftUI

/// `S1_OPEN=liveactivity` puts the Lock Screen card on screen by itself.
///
/// The simulator screenshots the Lock Screen poorly (and there is no command
/// line way to lock it), so the card is checked here: it is the same
/// `ReadingLockScreenView` the widget extension draws, with a sample thread.
struct ReadingLiveActivityPreview: View {
    var body: some View {
        ReadingLockScreenView(
            title: "有生之年还能看到续作吗",
            pageLabel: "第 398/483 页",
            author: "eaglu",
            excerpt: "最近重看了一遍，还是觉得这一段的节奏最好，可惜后面收得太急。",
            progress: 0.82
        )
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(.systemGroupedBackground))
    }
}
#endif
