import SwiftUI
import UIKit

/// Full-screen picture viewer: one page per picture in the thread, so the
/// reader can swipe between them instead of closing and tapping the next one.
///
/// It has three ways out, because a full-screen cover has no system "back":
/// the 关闭 button, a pull down on a picture that is not zoomed, and a right
/// swipe that starts at the left edge.
struct ImageBrowser: View {
    let urls: [URL]
    @Binding var index: Int

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var savedCount = 0
    @State private var message: String?
    @State private var needsPermission = false
    /// How far the viewer has been pulled away from its resting place. Zero
    /// except while a dismissal drag is under the finger.
    @State private var pull: CGSize = .zero
    /// Only used to size the thresholds; read from the viewer's own frame.
    @State private var viewerSize: CGSize = .zero
    /// Which page is zoomed in, if any: while it is, a drag belongs to the
    /// picture and the pull below has to keep its hands off.
    @State private var zoomedPage: Int?
    /// Set once the current drag is claimed for closing, so a drag that starts
    /// vertical keeps that meaning all the way down.
    @State private var claimsDismiss = false

    private var isPictureZoomed: Bool { zoomedPage == index }

    private var currentURL: URL? {
        urls.indices.contains(index) ? urls[index] : urls.first
    }

    var body: some View {
        ZStack {
            // Fades as the viewer is pulled away, so the thread it sits on
            // shows through instead of the whole screen sliding over black.
            Color.black
                .opacity(1 - dismissProgress)
                .ignoresSafeArea()

            viewer
                .opacity(1 - 0.7 * dismissProgress)
                .scaleEffect(1 - 0.06 * dismissProgress)
                .offset(pull)
                // One container element the tests can ask "is the picture zoomed
                // in?" — the gesture arbitration depends on it, and the two
                // answers lead to very different drags.
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("image-viewer")
                .accessibilityValue(isPictureZoomed ? "zoomed" : "fit")
                .accessibilityAction(.escape) { dismiss() }
        }
        .background(sizeReader)
        // Clear rather than black: the backdrop above is what paints black, so
        // a pull reveals the post behind the cover. The zoom transition only
        // needs the picture, not the cover's own fill.
        .presentationBackground(.clear)
        // Scoped to this subtree instead of preferredColorScheme, which would
        // flip the whole window to dark and make the thread behind flash.
        .environment(\.colorScheme, .dark)
        .sensoryFeedback(.success, trigger: savedCount)
        .onAppear(perform: applyDebugPull)
        .onChange(of: index) {
            // A new page never starts out pulled, or half dragged away.
            pull = .zero
            claimsDismiss = false
        }
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

    private var viewer: some View {
        NavigationStack {
            TabView(selection: $index) {
                ForEach(Array(urls.enumerated()), id: \.offset) { offset, url in
                    ZoomableImage(url: url, onZoomChanged: { zoomed in
                        if zoomed {
                            zoomedPage = offset
                        } else if zoomedPage == offset {
                            zoomedPage = nil
                        }
                    })
                    .tag(offset)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: urls.count > 1 ? .automatic : .never))
            .background(Color.black.ignoresSafeArea())
            // Simultaneous, not exclusive: a sideways drag has to keep turning
            // the page, and only the vertical ones below are ours.
            .simultaneousGesture(pullGesture)
            .overlay(alignment: .leading) { backEdge }
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

    /// The width of a drag that starts at the very left edge, laid over the
    /// pager so the page turn does not fight it for the same finger. VoiceOver
    /// reaches the viewer's `escape` action instead, so the strip is invisible
    /// to it.
    private var backEdge: some View {
        Color.clear
            .frame(width: 22)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                // Measured against the screen: the strip itself moves down with
                // the viewer, and a gesture in its own space would chase itself.
                DragGesture(minimumDistance: 8, coordinateSpace: .global)
                    .onChanged { value in
                        let dx = value.translation.width
                        guard dx > abs(value.translation.height) else { return }
                        pull = CGSize(width: max(0, dx), height: 0)
                    }
                    .onEnded { value in
                        // Only a sideways drag that actually started here counts;
                        // a vertical one in the strip is not a back swipe.
                        let dx = value.translation.width
                        guard dx > 0, dx > abs(value.translation.height) else { return }
                        commitPull(distance: dx, predicted: value.predictedEndTranslation.width)
                    }
            )
            .accessibilityHidden(true)
    }

    private var sizeReader: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear { viewerSize = proxy.size }
                .onChange(of: proxy.size) { _, size in viewerSize = size }
        }
    }

    // MARK: - Pulling the viewer away

    /// A pull only counts as "close the viewer" once it is clearly more
    /// vertical than horizontal: anything flatter belongs to the pager.
    private func isPullingDown(_ value: DragGesture.Value) -> Bool {
        let dy = value.translation.height
        return dy > 0 && dy > abs(value.translation.width) * 1.4
    }

    /// Attached above the pager rather than inside a picture, so turning the
    /// page keeps working: the pager still sees every touch and takes the
    /// sideways ones. While a picture is zoomed in the page's own drag has the
    /// finger, and this one bows out.
    private var pullGesture: some Gesture {
        // Measured against the screen: the viewer itself moves down with the
        // finger, and a gesture in its own space would chase itself.
        DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .onChanged { value in
                guard !isPictureZoomed else { return }
                if !claimsDismiss {
                    guard isPullingDown(value) else { return }
                    claimsDismiss = true
                }
                pull = CGSize(width: 0, height: max(0, value.translation.height))
            }
            .onEnded { value in
                guard claimsDismiss else { return }
                claimsDismiss = false
                guard !isPictureZoomed else { return }
                commitPull(distance: value.translation.height,
                           predicted: value.predictedEndTranslation.height)
            }
    }

    /// How far a pull has to travel to fill the screen: half its height down,
    /// 70% of its width back. `pull` still holds the last live value when the
    /// finger lifts, so its axis says which one applies.
    private var pullSpan: CGFloat {
        pull.width > 0 ? max(1, viewerSize.width * 0.7) : max(1, viewerSize.height * 0.45)
    }

    /// 0…1, used only for the fade and the slight shrink behind the finger.
    private var dismissProgress: CGFloat {
        min(1, max(0, max(pull.width, pull.height) / pullSpan))
    }

    private func commitPull(distance: CGFloat, predicted: CGFloat) {
        // A flick counts even when the finger did not get far, so the gesture
        // feels like the system's own interactive dismissals.
        let closes = distance / pullSpan >= 0.28 || predicted / pullSpan >= 0.55
        guard closes else {
            withAnimation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.86)) {
                pull = .zero
            }
            return
        }
        // Left where the finger put it: the zoom transition then collapses the
        // picture from its current place instead of snapping it back first.
        dismiss()
    }

    /// `S1_PULL=<points>` opens the viewer already pulled down that far, and
    /// with `S1_PULL_CLOSE=1` lets go of it a moment later, so the fade and the
    /// way it hands over to the zoom transition can be filmed: the simulator
    /// cannot drag.
    private func applyDebugPull() {
        #if DEBUG
        guard let raw = DebugHooks.string("S1_PULL"), let value = Double(raw) else { return }
        pull = CGSize(width: 0, height: max(0, value))
        guard DebugHooks.flag("S1_PULL_CLOSE") else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(1500))
            commitPull(distance: value, predicted: value * 3)
        }
        #endif
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
///
/// One drag gesture pans the enlarged picture, and it only exists while the
/// picture is zoomed in: at scale 1 the pager keeps the finger, so turning the
/// page still works and the pull-to-close above never fights it.
private struct ZoomableImage: View {
    let url: URL
    /// Told whenever the picture passes in or out of being zoomed in, so the
    /// viewer knows whether a drag under the finger means "the picture" or
    /// "the whole viewer".
    let onZoomChanged: (Bool) -> Void

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
                // Only while zoomed in: with the gesture installed at scale 1 the
                // pager never sees a sideways drag and pages stop turning.
                .gesture(panGesture(in: size), including: currentZoom > 1 ? .all : .none)
                .simultaneousGesture(pinchGesture(in: size))
                .onTapGesture(count: 2, coordinateSpace: .local) { location in
                    doubleTap(at: location, in: size)
                }
                .onChange(of: url) {
                    zoom = 1
                    offset = .zero
                }
                .onChange(of: zoom) { onZoomChanged(zoom > 1) }
                .onAppear {
                    applyDebugZoom()
                    // Say it out loud on the way in as well: the viewer's
                    // gesture arbitration reads this, and a page that appears
                    // already zoomed (S1_ZOOM) must not depend on a change
                    // event that a fast machine might coalesce away.
                    onZoomChanged(currentZoom > 1)
                }
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
