import SwiftUI

/// Floating action in the bottom-trailing corner. One button, two states: reply,
/// and — once a quote has been followed — back to where the reader was. On
/// iOS 26 and later it is a real Liquid Glass button, so it picks up the same
/// material as the system chrome instead of a hand-drawn circle.
struct ThreadActionButton: View {
    enum Mode {
        case reply
        case back
    }

    let mode: Mode
    var action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if #available(iOS 26.0, *) {
            Button(action: action) {
                glyphs
                    .frame(width: 52, height: 52)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .tint(Color.accentColor)
            .accessibilityLabel(mode == .reply ? "回复本帖" : "返回到刚才的楼")
            .sensoryFeedback(.impact(weight: .light), trigger: mode)
            .padding(.trailing, 18)
            .padding(.bottom, 18)
        } else {
            Button(action: action) {
                glyphs
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(Color.accentColor, in: Circle())
                    .shadow(color: .black.opacity(0.22), radius: 8, y: 3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(mode == .reply ? "回复本帖" : "返回到刚才的楼")
            .sensoryFeedback(.impact(weight: .light), trigger: mode)
            .padding(.trailing, 18)
            .padding(.bottom, 18)
        }
    }

    /// Both glyphs share one font, so the two states keep the same weight; the
    /// outgoing one turns and shrinks away while the incoming one lands.
    private var glyphs: some View {
        ZStack {
            glyph(.reply).modifier(SwapTransition(isActive: mode == .reply, reduceMotion: reduceMotion))
            glyph(.back).modifier(SwapTransition(isActive: mode == .back, reduceMotion: reduceMotion))
        }
    }

    private func glyph(_ glyphMode: Mode) -> some View {
        Image(systemName: glyphMode == .reply ? "arrow.turn.up.left" : "arrow.backward.to.line")
            .font(.system(size: 20, weight: .semibold))
    }
}

/// Turning one glyph out while the other turns in, so the change reads as a
/// single control swapping purpose rather than a second button appearing.
private struct SwapTransition: ViewModifier {
    let isActive: Bool
    let reduceMotion: Bool

    private var turn: Double { reduceMotion ? 0 : (isActive ? 0 : (isActive ? 120 : -120)) }

    func body(content: Content) -> some View {
        content
            .opacity(isActive ? 1 : 0)
            .rotationEffect(.degrees(isActive ? 0 : 120))
            .scaleEffect(isActive ? 1 : (reduceMotion ? 1 : 0.72))
            .animation(
                reduceMotion
                    ? .easeInOut(duration: 0.2)
                    : .spring(response: 0.42, dampingFraction: 0.72),
                value: isActive
            )
    }
}
