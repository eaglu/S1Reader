import SwiftUI
import UIKit

/// The display corner radius, so pictures can be cut by the same curve as the
/// device instead of a small fixed card radius.
///
/// SwiftUI does not expose it, and `ConcentricRectangle` resolves to a zero
/// radius inside a plain scroll row (only its `minimum` survives), while
/// `ContainerRelativeShape` resolves asymmetrically when the view is inset from
/// the screen edges. Reading the radius once and drawing an explicit rounded
/// rectangle keeps every corner identical.
enum DeviceGeometry {
    /// Radius of the screen's rounded corners in points, e.g. 55 on a Pro Max.
    static let screenCornerRadius: CGFloat = {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let screen = scenes.first?.screen ?? UIScreen.main
        if let radius = screen.value(forKey: "_displayCornerRadius") as? CGFloat, radius > 0 {
            #if DEBUG
            print("S1 device corner radius \(radius)")
            #endif
            return radius
        }
        #if DEBUG
        print("S1 device corner radius unavailable, using 40")
        #endif
        // Fall back to a value close to current iPhones rather than square corners.
        return 40
    }()
}

/// Rounds a view with the device corner curve, reduced by `inset` so a picture
/// sitting inside the screen keeps the same concentric shape as the display.
struct DeviceCornerShape: Shape {
    /// Distance between the view and the screen edge it is concentric with.
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let radius = max(0, DeviceGeometry.screenCornerRadius - inset)
        return RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect)
    }
}
