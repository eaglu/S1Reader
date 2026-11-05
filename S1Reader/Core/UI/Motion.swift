import SwiftUI

/// iOS 18 keeps the reader oriented by expanding the tapped picture from its
/// place in the post instead of sliding a panel over it. Older systems keep the
/// plain cover: the HIG asks for continuity, not for a specific trick.
struct ZoomSource: ViewModifier {
    let id: String
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        #if os(iOS)
        if #available(iOS 18.0, *), let namespace {
            content.matchedTransitionSource(id: id, in: namespace)
        } else {
            content
        }
        #else
        content
        #endif
    }
}

/// The other half of the picture zoom: the presented viewer grows out of (and
/// collapses back into) the thumbnail it came from.
struct ZoomPresentation: ViewModifier {
    let id: String?
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        #if os(iOS)
        if #available(iOS 18.0, *), let id {
            content.navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            content
        }
        #else
        content
        #endif
    }
}

extension View {
    func zoomSource(id: String, in namespace: Namespace.ID?) -> some View {
        modifier(ZoomSource(id: id, namespace: namespace))
    }

    func zoomPresentation(id: String?, in namespace: Namespace.ID) -> some View {
        modifier(ZoomPresentation(id: id, namespace: namespace))
    }
}
