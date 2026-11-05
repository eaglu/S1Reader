import SwiftUI
import UIKit

/// A compact, non-blocking notice for something that failed while the screen
/// still has content to read — a page that would not load, a refresh that timed
/// out. Alerts are reserved for things the reader must decide about, so this
/// stays inline and dismissible.
struct InlineNotice: View {
    let message: String
    var systemImage: String = "exclamationmark.triangle"
    var retryTitle: String? = "重试"
    var onRetry: (() -> Void)?
    var onDismiss: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(.orange)
                .font(.footnote.weight(.semibold))
                .accessibilityHidden(true)

            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let retryTitle, let onRetry {
                Button(retryTitle, action: onRetry)
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.borderless)
            }
            if let onDismiss {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("关闭提示")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// Fades an inline notice in and out instead of letting it pop.
    func noticeTransition(reduceMotion: Bool) -> some View {
        transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
    }
}
