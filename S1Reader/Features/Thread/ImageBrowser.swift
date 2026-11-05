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

/// A single picture that fits the screen and can be pinched, dragged or
/// double-tapped. The zoom is anchored at the tapped point and the picture is
/// clipped to the viewport, so zooming in never strands you in a corner.
private struct ZoomableImage: View {
    let url: URL

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var zoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @GestureState private var pinch: CGFloat = 1
    @GestureState private var pan: CGSize = .zero

    private static let maxZoom: CGFloat = 4
    private static let doubleTapZoom: CGFloat = 2.5

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            RemoteImage(url: url, contentMode: .fit, startsLoadingImmediately: true)
                .frame(width: size.width, height: size.height)
                .scaleEffect(currentZoom)
                .offset(visibleOffset(in: size))
                .frame(width: size.width, height: size.height)
                .contentShape(Rectangle())
                .gesture(panGesture(in: size))
                .simultaneousGesture(pinchGesture(in: size))
                .onTapGesture(count: 2, coordinateSpace: .local) { location in
                    doubleTap(at: location, in: size)
                }
                .onChange(of: url) {
                    zoom = 1
                    offset = .zero
                }
                .onAppear(perform: applyDebugZoom)
                .accessibilityLabel("图片")
        }
        .background(Color.black)
    }

    private var currentZoom: CGFloat {
        min(max(1, zoom * pinch), Self.maxZoom)
    }

    /// How far the picture can travel before its edge leaves the viewport.
    private func limit(in size: CGSize, zoom: CGFloat) -> CGSize {
        CGSize(width: max(0, size.width * (zoom - 1) / 2),
               height: max(0, size.height * (zoom - 1) / 2))
    }

    private func clamped(_ value: CGSize, in size: CGSize, zoom: CGFloat) -> CGSize {
        let limit = limit(in: size, zoom: zoom)
        return CGSize(width: min(max(value.width, -limit.width), limit.width),
                      height: min(max(value.height, -limit.height), limit.height))
    }

    private func visibleOffset(in size: CGSize) -> CGSize {
        clamped(CGSize(width: offset.width + pan.width, height: offset.height + pan.height),
                in: size,
                zoom: currentZoom)
    }

    private func panGesture(in size: CGSize) -> some Gesture {
        DragGesture()
            .updating($pan) { value, state, _ in
                guard currentZoom > 1 else { return }
                state = value.translation
            }
            .onEnded { value in
                guard currentZoom > 1 else { return }
                let moved = CGSize(width: offset.width + value.translation.width,
                                   height: offset.height + value.translation.height)
                offset = clamped(moved, in: size, zoom: currentZoom)
            }
    }

    private func pinchGesture(in size: CGSize) -> some Gesture {
        MagnifyGesture()
            .updating($pinch) { value, state, _ in
                state = value.magnification
            }
            .onEnded { value in
                let target = min(max(1, zoom * value.magnification), Self.maxZoom)
                withAnimation(reduceMotion ? nil : .snappy) {
                    zoom = target
                    offset = target == 1 ? .zero : clamped(offset, in: size, zoom: target)
                }
            }
    }

    /// Scaling happens about the centre, so keeping the tapped point under the
    /// finger means shifting the whole view by `(point - centre) * (1 - zoom)`.
    private func doubleTap(at location: CGPoint, in size: CGSize) {
        let target = zoom > 1 ? 1 : Self.doubleTapZoom
        let shift = CGSize(width: (location.x - size.width / 2) * (1 - target),
                           height: (location.y - size.height / 2) * (1 - target))
        withAnimation(reduceMotion ? nil : .snappy) {
            zoom = target
            offset = target == 1 ? .zero : clamped(shift, in: size, zoom: target)
        }
    }

    /// `S1_ZOOM=<scale>` opens the viewer already zoomed, so the anchored
    /// framing can be checked from a screenshot (the simulator cannot tap).
    private func applyDebugZoom() {
        #if DEBUG
        guard let raw = ProcessInfo.processInfo.environment["S1_ZOOM"],
              let value = Double(raw), value > 1 else { return }
        zoom = min(max(1, value), Self.maxZoom)
        #endif
    }
}
