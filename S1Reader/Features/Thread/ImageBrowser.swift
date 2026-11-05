import SwiftUI
import UIKit

/// Full-screen picture viewer: one page per picture in the thread, so the
/// reader can swipe between them instead of closing and tapping the next one.
struct ImageBrowser: View {
    let urls: [URL]
    @Binding var index: Int

    @Environment(\.dismiss) private var dismiss
    @State private var savedCount = 0
    @State private var message: String?
    @State private var needsPermission = false

    private var currentURL: URL? {
        urls.indices.contains(index) ? urls[index] : urls.first
    }

    var body: some View {
        ZStack {
            // Painted from the first frame so the sheet never flashes the system
            // background while it animates in or while pages swipe.
            Color.black.ignoresSafeArea()

            NavigationStack {
            TabView(selection: $index) {
                ForEach(Array(urls.enumerated()), id: \.offset) { offset, url in
                    ZoomableImage(url: url)
                        .tag(offset)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: urls.count > 1 ? .automatic : .never))
            .background(Color.black.ignoresSafeArea())
            .navigationTitle(urls.count > 1 ? "\(index + 1) / \(urls.count)" : "图片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task { await save() }
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .accessibilityLabel("保存到相册")
                }
                if let currentURL {
                    ToolbarItem(placement: .topBarLeading) {
                        ShareLink(item: currentURL) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("分享图片")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            }
        }
        .presentationBackground(Color.black)
        // Scoped to this subtree instead of preferredColorScheme, which would
        // flip the whole window to dark and make the thread behind flash.
        .environment(\.colorScheme, .dark)
        .sensoryFeedback(.success, trigger: savedCount)
        .alert(message ?? "", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("好", role: .cancel) { message = nil }
            if needsPermission {
                Button("去设置") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                    message = nil
                }
            }
        }
    }

    private func save() async {
        guard let url = currentURL else { return }
        do {
            try await ImageSaver.save(url)
            needsPermission = false
            savedCount += 1
            message = "已保存到相册"
        } catch {
            needsPermission = (error as? ImageSaveError) == .denied
            message = error.localizedDescription
        }
    }
}

/// A single picture that fits the screen and can be pinched or double-tapped.
private struct ZoomableImage: View {
    let url: URL

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scale: CGFloat = 1

    var body: some View {
        GeometryReader { proxy in
            ScrollView([.horizontal, .vertical]) {
                // Fitting the picture into the viewport height as well as its
                // width is what shows the whole image instead of its top
                // slice; the trailing frame reserves scroll space when zoomed.
                RemoteImage(url: url, contentMode: .fit, startsLoadingImmediately: true)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .scaleEffect(scale)
                    .frame(width: proxy.size.width * scale, height: proxy.size.height * scale)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
            .gesture(
                MagnifyGesture()
                    .onChanged { value in
                        scale = min(max(1, value.magnification), 4)
                    }
                    .onEnded { value in
                        withAnimation(reduceMotion ? nil : .snappy) {
                            scale = min(max(1, value.magnification), 4)
                        }
                    }
            )
            .onTapGesture(count: 2) {
                withAnimation(reduceMotion ? nil : .snappy) { scale = scale > 1 ? 1 : 2.5 }
            }
            .accessibilityLabel("图片")
        }
        .background(Color.black)
    }
}
