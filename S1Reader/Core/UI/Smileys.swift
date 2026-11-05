import SwiftUI
import UIKit

/// The `face2017` smiley set S1 uses, bundled with the app so common smileys
/// never touch the network. Anything this build does not carry (older sets or
/// per-forum custom smileys) still goes through `ImageLoader` as before.
enum Smileys {
    /// Bundled assets are named `smiley001` … `smiley279`, matching the numeric
    /// file names under `static.stage1st.com/image/smiley/face2017/`.
    static func bundled(_ url: URL) -> UIImage? {
        guard let code = code(for: url) else { return nil }
        return UIImage(named: "smiley\(code)")
    }

    /// Nil for anything that is not a numeric face2017 smiley.
    private static func code(for url: URL) -> String? {
        let name = url.deletingPathExtension().lastPathComponent
        guard !name.isEmpty, name.allSatisfy(\.isNumber) else { return nil }
        return String(format: "%03d", Int(name) ?? 0)
    }
}
