import SwiftUI

/// A short, non-blocking confirmation ("已收藏", "已清除 3 张缓存").
///
/// Per the HIG, feedback should match the weight of the action: a toast for
/// things that succeeded (or quietly did not), an alert only for decisions the
/// reader has to make.
struct ToastMessage: Identifiable, Equatable {
    enum Style {
        case info
        case success
        case warning

        var systemImage: String {
            switch self {
            case .info: "info.circle.fill"
            case .success: "checkmark.circle.fill"
            case .warning: "exclamationmark.triangle.fill"
            }
        }

        var tint: Color {
            switch self {
            case .info: .secondary
            case .success: .green
            case .warning: .orange
            }
        }
    }

    let id = UUID()
    var text: String
    var style: Style = .info
    var duration: Duration = .milliseconds(2200)
}

private struct ToastModifier: ViewModifier {
    @Binding var message: ToastMessage?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let message {
                    HStack(spacing: 8) {
                        Image(systemName: message.style.systemImage)
                            .foregroundStyle(message.style.tint)
                        Text(message.text)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
                    .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 96)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .opacity.combined(with: .move(edge: .bottom))
                    )
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isStaticText)
                    .task(id: message.id) {
                        try? await Task.sleep(for: message.duration)
                        withAnimation(.easeOut(duration: 0.2)) { self.message = nil }
                    }
                }
            }
            .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.82), value: message)
    }
}

extension View {
    /// Shows a toast above the floating action button and dismisses it on its own.
    func toast(_ message: Binding<ToastMessage?>) -> some View {
        modifier(ToastModifier(message: message))
    }
}
