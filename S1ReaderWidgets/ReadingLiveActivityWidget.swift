import ActivityKit
import SwiftUI
import WidgetKit

/// Renders the thread the reader left behind: the Lock Screen card, the
/// expanded island and both compact forms.
///
/// Colours are semantic (`.primary`, `.secondary`, `.tint`) and nothing sets a
/// fixed font size, so the card follows light/dark and Dynamic Type the same way
/// the app does. Live Activity views are rendered out of process and cannot read
/// the app's environment, so the app's theme is not available here anyway.
struct ReadingLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ReadingActivityAttributes.self) { context in
            ReadingLockScreenView(context: context)
                // Tapping anywhere on the card opens the thread at that page.
                .widgetURL(link(for: context))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "text.book.closed.fill")
                        .font(.title3)
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.compactPageLabel)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 6) {
                        Text(context.state.pageLabel)
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        Label("继续阅读", systemImage: "chevron.forward")
                            .font(.caption.weight(.semibold))
                            .labelStyle(.titleAndIcon)
                    }
                }
            } compactLeading: {
                Image(systemName: "text.book.closed.fill")
                    .foregroundStyle(.tint)
                    .accessibilityLabel("正在阅读")
            } compactTrailing: {
                Text(context.state.compactPageLabel)
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            } minimal: {
                Image(systemName: "text.book.closed.fill")
                    .foregroundStyle(.tint)
                    .accessibilityLabel("正在阅读")
            }
            .widgetURL(link(for: context))
            .keylineTint(.accentColor)
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
