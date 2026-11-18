import SwiftUI
import WidgetKit

/// The extension's only widget: the reading Live Activity.
///
/// A Live Activity has to be declared by a widget extension even though it is
/// never picked from the widget gallery; the `ActivityConfiguration` below is
/// what ActivityKit asks for when the app starts one.
@main
struct S1ReaderWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ReadingLiveActivityWidget()
    }
}
