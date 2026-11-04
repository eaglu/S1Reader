import Foundation

/// S1 stores avatars on a static host using a path derived from the user id:
/// uid 464256 → `000/46/42/56_avatar_middle.jpg`.
enum AvatarURL {
    enum Size: String {
        case small   // 48×48
        case middle  // 120×120
        case big     // 200×200
    }

    static func url(uid: String, size: Size = .middle) -> URL? {
        guard let value = Int(uid), value > 0 else { return nil }
        let digits = String(format: "%09d", value)
        guard digits.count == 9 else { return nil }
        let chars = Array(digits)
        let path = [
            String(chars[0...2]),
            String(chars[3...4]),
            String(chars[5...6]),
            String(chars[7...8])
        ].joined(separator: "/")
        return URL(string: "https://avatar.stage1st.com/\(path)_avatar_\(size.rawValue).jpg")
    }
}
