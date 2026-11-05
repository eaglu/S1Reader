import SwiftUI

/// On iPad the tab bar turns into a sidebar, which is what the HIG asks for
/// when there is room; iPhone keeps the bottom tab bar.
struct SidebarAdaptableTabs: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.tabViewStyle(.sidebarAdaptable)
        } else {
            content
        }
    }
}

/// Keeps long text lines readable on wide screens instead of stretching a post
/// across the whole iPad display.
struct ReadableWidth: ViewModifier {
    @Environment(\.horizontalSizeClass) private var sizeClass

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: sizeClass == .regular ? 760 : .infinity)
            .frame(maxWidth: .infinity)
    }
}

/// `plain` rows read best on iPhone; grouped insets look right on iPad.
struct AdaptiveThreadListStyle: ViewModifier {
    @Environment(\.horizontalSizeClass) private var sizeClass

    func body(content: Content) -> some View {
        if sizeClass == .regular {
            content.listStyle(.insetGrouped)
        } else {
            content.listStyle(.plain)
        }
    }
}
