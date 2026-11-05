import SwiftUI

/// Rounds a view with the corner curve of whatever contains it. Inside a screen
/// that resolves to the display corner radius, so pictures get cut by the same
/// curve as the device instead of a small fixed card radius.
///
/// `ConcentricRectangle` was the first attempt, but inside a plain scroll row it
/// resolves to a radius of 0 (only the `minimum` survives), which is why the
/// corner here comes from `ContainerRelativeShape` — that one does pick up the
/// window's corner radius.
struct DeviceCornerShape: Shape {
    func path(in rect: CGRect) -> Path {
        if #available(iOS 26.0, *) {
            return ContainerRelativeShape().path(in: rect)
        }
        // Older systems resolve the container shape inconsistently outside
        // sheets, so approximate the same look with a fixed continuous radius.
        return RoundedRectangle(cornerRadius: 34, style: .continuous).path(in: rect)
    }
}
