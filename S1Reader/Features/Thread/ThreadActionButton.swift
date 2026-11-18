import SwiftUI

/// Floating action in the bottom-trailing corner. One button, two states: reply,
/// and — once a quote has been followed — back to where the reader was. On
/// iOS 26 and later it is a real Liquid Glass button, so it picks up the same
/// material as the system chrome instead of a hand-drawn circle. Both states
/// keep that glass and both glyphs are `.primary`, so switching states changes
/// the shape alone — never the colour.
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
            glassButton
        } else {
            fallbackButton
        }
    }

    @available(iOS 26.0, *)
    private var glassButton: some View {
        Button(action: action) {
            glyphs
                .frame(width: 52, height: 52)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        // No `.tint`: a tinted glass button paints its glass with the tint and
        // pushes the glyph to white, which is what made reply and back differ in
        // colour. Untinted glass lets both glyphs sit in the system label colour,
        // which already follows the appearance.
        .accessibilityLabel(accessibilityLabel)
        .sensoryFeedback(.impact(weight: .light), trigger: mode)
        .padding(.trailing, 18)
        .padding(.bottom, 18)
    }

    private var fallbackButton: some View {
        Button(action: action) {
            glyphs
                .foregroundStyle(Color.primary)
                .frame(width: 52, height: 52)
                // A material circle keeps the glyph legible in both
                // appearances; white on the accent fill was 2.6:1 in dark
                // mode, under the 3:1 a large glyph needs.
                .background(.regularMaterial, in: Circle())
                .overlay {
                    Circle().strokeBorder(Color.primary.opacity(0.08))
                }
                .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .sensoryFeedback(.impact(weight: .light), trigger: mode)
        .padding(.trailing, 18)
        .padding(.bottom, 18)
    }

    private var accessibilityLabel: String {
        mode == .reply ? "回复本帖" : "返回到刚才的楼"
    }

    /// Both glyphs share one slot and one colour, so the two states keep the
    /// same weight; the outgoing one turns and shrinks away while the incoming
    /// one lands. Their ink is matched (23.4 x 20.2pt against 21.2 x 20.2pt),
    /// but the shapes are deliberately different: a closed reply arrow versus a
    /// thin way-back line.
    private var glyphs: some View {
        ZStack {
            glyph(.reply).modifier(SwapTransition(isActive: mode == .reply, reduceMotion: reduceMotion))
            glyph(.back).modifier(SwapTransition(isActive: mode == .back, reduceMotion: reduceMotion))
        }
    }

    @ViewBuilder
    private func glyph(_ glyphMode: Mode) -> some View {
        switch glyphMode {
        case .reply:
            // The outlined reply arrow, not `arrow.turn.up.left`: that one is a
            // thin leftward line with a bend, which at 52pt read as a twin of
            // the thin line `ReturnGlyph` below. This is the system's reply
            // silhouette — a broad closed arrow, so the two states differ in
            // shape language and not just in direction. 22pt puts its ink at
            // 23.4 x 20.2pt against the way-back glyph's 21.2 x 20.2pt, so the
            // swap keeps the same optical size.
            Image(systemName: "arrowshape.turn.up.left")
                .font(.system(size: 22, weight: .semibold))
        case .back:
            ReturnGlyph()
        }
    }
}

/// The way-back arrow: two leftward arms joined by a bend on the right, the
/// upper one ending in an arrowhead. Drawn rather than taken from SF Symbols
/// because `arrow.uturn.left` carries a vertical tail the design does not have,
/// and its stroke is thinner than the reference.
struct ReturnGlyph: View {
    /// 27pt canvas: about 21pt of ink, the 40% of a 52pt button that keeps this
    /// arrow the same optical size as the reply symbol beside it.
    var size: CGFloat = 27
    var lineWidth: CGFloat = 2.7

    var body: some View {
        ReturnGlyphShape()
            .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// Laid out in a 27pt square and scaled to the frame it is given, so the
/// proportions hold at any size. The bend is a true semicircle built from two
/// quarter arcs, which keeps it smooth without depending on the arc direction
/// conventions of a flipped coordinate space.
struct ReturnGlyphShape: Shape {
    private static let designSize: CGFloat = 27

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / Self.designSize
        let origin = CGPoint(
            x: rect.midX - Self.designSize * scale / 2,
            y: rect.midY - Self.designSize * scale / 2
        )
        func point(_ horizontal: CGFloat, _ vertical: CGFloat) -> CGPoint {
            CGPoint(x: origin.x + horizontal * scale, y: origin.y + vertical * scale)
        }

        let bendX: CGFloat = 16.5
        let bendY: CGFloat = 15.7
        let radius: CGFloat = 6.5
        let upperY = bendY - radius
        let lowerY = bendY + radius
        // How far a quarter arc's control points reach from its corner.
        let reach = radius * 0.5522847498
        let rightX = bendX + radius
        let tip = point(4.5, upperY)

        var path = Path()
        // Lower arm, then up and around the bend, then the upper arm.
        path.move(to: point(10, lowerY))
        path.addLine(to: point(bendX, lowerY))
        path.addCurve(
            to: point(rightX, bendY),
            control1: point(bendX + reach, lowerY),
            control2: point(rightX, bendY + reach)
        )
        path.addCurve(
            to: point(bendX, upperY),
            control1: point(rightX, bendY - reach),
            control2: point(bendX + reach, upperY)
        )
        path.addLine(to: tip)

        // Arrowhead, drawn as its own stroke so the tip stays rounded.
        let barb: CGFloat = 4.4
        let barbX: CGFloat = 9.4
        path.move(to: point(barbX, upperY - barb))
        path.addLine(to: tip)
        path.addLine(to: point(barbX, upperY + barb))
        return path
    }
}

/// Turning one glyph out while the other turns in, so the change reads as a
/// single control swapping purpose rather than a second button appearing.
private struct SwapTransition: ViewModifier {
    let isActive: Bool
    let reduceMotion: Bool

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

#Preview("Action button") {
    VStack(spacing: 0) {
        ForEach([ThreadActionButton.Mode.reply, .back], id: \.self) { mode in
            ThreadActionButton(mode: mode) {}
        }
    }
    .padding(24)
    .preferredColorScheme(.light)
}

#Preview("Action button — dark") {
    VStack(spacing: 0) {
        ForEach([ThreadActionButton.Mode.reply, .back], id: \.self) { mode in
            ThreadActionButton(mode: mode) {}
        }
    }
    .padding(24)
    .preferredColorScheme(.dark)
}
