import SwiftUI
import UIKit

/// Circular avatar that falls back to the author's initial while loading,
/// and stays on the initial when the user has no avatar (S1 returns 404).
struct AvatarView: View {
    let uid: String
    let name: String
    var size: CGFloat = 24

    @State private var image: UIImage?

    private var initial: String {
        String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.15))

            Text(initial)
                .font(.system(size: size * 0.46, weight: .bold))
                .foregroundStyle(Color.accentColor)

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.primary.opacity(0.06)))
        // The author's name is always shown next to the avatar, so VoiceOver
        // would only repeat it.
        .accessibilityHidden(true)
        .task(id: uid) {
            guard image == nil, let url = AvatarURL.url(uid: uid) else { return }
            if let loaded = await ImageLoader.shared.image(for: url) {
                image = loaded
            }
        }
    }
}
