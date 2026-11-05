import SwiftUI
import UIKit

/// One placeholder bar. Building the skeletons from shapes (instead of redacted
/// text) keeps the loading state quiet and cheap.
///
/// The highlight is a gradient drawn *inside* the bar: masking an external
/// gradient with the placeholder content froze the animation inside `List`
/// rows, so each bar carries its own sweep instead.
struct SkeletonBar: View {
    var width: CGFloat?
    var height: CGFloat = 12

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: height / 2, style: .continuous)
    }

    var body: some View {
        Group {
            if reduceMotion {
                shape.fill(Color(uiColor: .tertiarySystemFill))
            } else {
                TimelineView(.animation) { timeline in
                    let phase = timeline.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: 1.6) / 1.6
                    shape
                        .fill(Color(uiColor: .tertiarySystemFill))
                        .overlay {
                            LinearGradient(
                                colors: [.clear, Color.white.opacity(0.55), .clear],
                                startPoint: UnitPoint(x: phase * 1.8 - 0.4, y: 0.5),
                                endPoint: UnitPoint(x: phase * 1.8 + 0.2, y: 0.5)
                            )
                            .clipShape(shape)
                        }
                }
            }
        }
        .frame(width: width, height: height)
        .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }
}
