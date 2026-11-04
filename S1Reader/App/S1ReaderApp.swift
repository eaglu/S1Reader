import SwiftUI

@main
struct S1ReaderApp: App {
    @State private var model = AppModel()

    init() {
        #if DEBUG
        // S1_SAVE_IMAGE=<url> exercises the photo-library save path from the CLI,
        // which the simulator cannot reach by tapping.
        if let raw = ProcessInfo.processInfo.environment["S1_SAVE_IMAGE"],
           let url = URL(string: raw) {
            Task {
                do {
                    try await ImageSaver.save(url)
                    print("S1_SAVE_IMAGE ok")
                } catch {
                    print("S1_SAVE_IMAGE failed: \(error.localizedDescription)")
                }
            }
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
    }
}
