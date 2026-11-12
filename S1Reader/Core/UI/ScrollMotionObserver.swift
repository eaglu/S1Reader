import SwiftUI

/// Reports where the list is scrolled and whether it has come to rest.
///
/// A prepended page has to be anchored to the floor the reader was on, but not
/// while their finger is still pulling: an active scroll keeps writing the top
/// row back into the scroll position binding and throws the anchor away. Waiting
/// for the list to rest is the only moment a programmatic scroll sticks.
///
/// Nothing is reported before iOS 18, where the geometry is not observable.
struct ScrollMotionObserver: ViewModifier {
    /// Content offset in points; negative is pulled past the top.
    let onOffset: (CGFloat) -> Void
    /// `true` once the list is at rest (finger up, bounce and deceleration done).
    let onSettled: (Bool) -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentOffset.y
                } action: { _, offset in
                    onOffset(offset)
                }
                .onScrollPhaseChange { _, phase in
                    onSettled(phase == .idle)
                }
        } else {
            content
        }
    }
}
