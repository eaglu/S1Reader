import ActivityKit
import SwiftUI
import WidgetKit

/// Renders the thread the reader left behind: the Lock Screen card, the
/// expanded island and both compact forms.
///
/// The island is a glance too, so each form carries one idea: the compact pair
/// is page → progress, the expanded form is icon + title + page, with the
/// excerpt under it. Colours are semantic (`.primary`, `.secondary`,
/// `.tertiary`) and no font size is fixed, so light/dark and Dynamic Type work
/// the way they do in the app. Live Activity views are rendered out of process
/// and cannot read the app's environment, so the app's theme is not available
/// here anyway.
struct ReadingLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ReadingActivityAttributes.self) { context in
            ReadingLockScreenView(context: context)
                // Tapping anywhere on the card opens the thread at that page.
                .widgetURL(link(for: context))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "text.book.closed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.compactPageLabel)
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        // The expanded island's corner curves into the trailing
                        // region; without this the last digit is clipped.
                        .padding(.trailing, 10)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        // The island has its own sizing; the cap keeps an
                        // accessibility size from crowding the page label.
                        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        // The page is already in the trailing region; the
                        // bottom line is the excerpt plus the percentage.
                        Text(context.state.excerpt)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 8)
                        Text(context.state.progressLabel)
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(.tertiary)
                    }
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                }
            } compactLeading: {
                // Numbers only: the island is too small for a wordy label.
                Text(context.state.compactPageLabel)
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                    .accessibilityLabel("正在阅读 \(context.state.pageLabel)")
            } compactTrailing: {
                Text(context.state.progressLabel)
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                    .accessibilityLabel("阅读进度 \(context.state.progressLabel)")
            } minimal: {
                Image(systemName: "text.book.closed")
                    .foregroundStyle(.primary)
                    .accessibilityLabel("正在阅读")
            }
            .widgetURL(link(for: context))
        }
    }

    /// The same deep link the app understands: `s1reader://thread?tid=&page=`.
    private func link(for context: ActivityViewContext<ReadingActivityAttributes>) -> URL {
        ReadingActivityAttributes.deepLink(
            tid: context.attributes.tid,
            page: context.state.page
        )
    }
}

/// The card lives in `Shared/` so a preview and the app's debug screen can
/// render it too; this is what feeds it from the activity context.
extension ReadingLockScreenView {
    init(context: ActivityViewContext<ReadingActivityAttributes>) {
        let state = context.state
        self.init(
            title: state.title,
            pageLabel: state.pageLabel,
            author: state.author,
            excerpt: state.excerpt,
            progress: state.progress
        )
    }
}
