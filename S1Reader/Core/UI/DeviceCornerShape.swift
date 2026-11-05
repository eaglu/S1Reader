import SwiftUI

/// Rounds a view so its corners stay concentric with the corners of whatever
/// contains it — on iOS 26+ that resolves to the device/sheet corner radius, so
/// pictures look like they belong to the screen instead of being a 10pt card.
struct DeviceCornerShape: Shape {
    /// Smallest radius used when the view is far from a screen corner.
    var minimum: CGFloat = 12

    func path(in rect: CGRect) -> Path {
        if #available(iOS 26.0, *) {
            return ConcentricRectangle(
                corners: .concentric(minimum: .fixed(minimum)),
                isUniform: true
            ).path(in: rect)
        }
        // iOS 17–18 does not expose the display corner radius, so approximate
        // the same look with a fixed continuous radius.
        return RoundedRectangle(cornerRadius: 34, style: .continuous).path(in: rect)
    }
}
