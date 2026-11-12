import Foundation

/// Development hooks driven by launch environment variables.
///
/// The simulator cannot be tapped from the command line, so screens expose
/// `S1_*` switches that put them into a particular state for screenshots and
/// films. Every body here compiles away in release builds, but the call sites
/// stay readable: a screen makes one call instead of spreading `#if DEBUG`
/// through its layout and view-model code.
enum DebugHooks {
    /// Value of a launch-environment variable. Always `nil` in release.
    static func string(_ key: String) -> String? {
        #if DEBUG
        ProcessInfo.processInfo.environment[key]
        #else
        nil
        #endif
    }

    static func int(_ key: String) -> Int? {
        string(key).flatMap(Int.init)
    }

    static func flag(_ key: String) -> Bool {
        string(key) != nil
    }

    /// Prints only in debug builds. The message is an autoclosure, so nothing
    /// is formatted in release either.
    static func log(_ message: @autoclosure () -> String) {
        #if DEBUG
        print(message())
        #endif
    }

    /// `S1_MOTION_SLOW=<factor>` stretches transitions so they can be filmed.
    static var motionScale: Double {
        #if DEBUG
        if let raw = string("S1_MOTION_SLOW"), let factor = Double(raw) {
            return max(1, factor)
        }
        #endif
        return 1
    }

    /// Signed-in fixtures for the account screens (`S1_DEMO=1`). `nil` when the
    /// demo mode is off or the build is a release.
    static var demoNotices: [Notice]? {
        #if DEBUG
        DemoMode.isEnabled ? DemoMode.notices : nil
        #else
        nil
        #endif
    }

    static var demoFavorites: [FavoriteThread]? {
        #if DEBUG
        DemoMode.isEnabled ? DemoMode.favorites : nil
        #else
        nil
        #endif
    }

    /// `S1_PERF_BENCH=1` measures the two ways a post body is scanned for
    /// pictures. Returns the printable line, or `nil` when the benchmark is off.
    static func imageScanBenchmark(_ htmls: [String]) async -> String? {
        #if DEBUG
        guard flag("S1_PERF_BENCH") else { return nil }
        let fastStart = Date()
        _ = await Task.detached(priority: .utility) {
            htmls.flatMap { HTMLParser.imageURLs(in: $0) }
        }.value
        let fast = Date().timeIntervalSince(fastStart) * 1000

        let slowStart = Date()
        _ = await Task.detached(priority: .utility) {
            htmls.flatMap { html in
                HTMLParser.parse(html).compactMap { node -> URL? in
                    if case .image(let url, let isSmiley) = node, !isSmiley { return url }
                    return nil
                }
            }
        }.value
        let slow = Date().timeIntervalSince(slowStart) * 1000
        return "S1_PERF imageURLs posts=\(htmls.count)"
            + " scan=\(String(format: "%.1f", fast))ms fullParse=\(String(format: "%.1f", slow))ms"
        #else
        _ = htmls
        return nil
        #endif
    }
}

/// The `S1_*` rehearsal script for the thread detail screen.
///
/// It drives the same actions a reader would (jump, load earlier, follow a
/// quote, open a picture) through closures the view hands in, so the view keeps
/// no debug branches of its own and this file needs no access to its state.
@MainActor
struct ThreadDetailDebugScript {
    /// What the script can do on the screen.
    struct Hooks {
        var model: ThreadDetailViewModel
        /// Jump to a floor, remembering `from` as the way back.
        var jump: (_ pid: String, _ from: String?) async -> Void
        var returnToOrigin: () -> Void
        var loadEarlier: (_ force: Bool) async -> Void
        var reveal: (_ pid: String) -> Void
        var setVisiblePid: (_ pid: String?) -> Void
        var showPageJump: () -> Void
        var openImage: (_ url: URL) -> Void
        var showToast: (_ message: ToastMessage) -> Void
        var dismiss: () -> Void
        var clearThreadImageCache: () -> Void
    }

    let hooks: Hooks

    func run() async {
        #if DEBUG
        await rehearse()
        #endif
    }

    #if DEBUG
    private func rehearse() async {
        let model = hooks.model
        let env = DebugHooks.string

        // S1_LOADMORE=<n> appends n pages so pagination can be checked.
        if let times = DebugHooks.int("S1_LOADMORE") {
            for _ in 0..<max(0, times) {
                try? await Task.sleep(for: .milliseconds(500))
                await model.loadMore()
                // S1_FRESH_SCROLL=1 reveals the rows that just arrived so the
                // entrance can be filmed (they normally land off-screen).
                if env("S1_FRESH_SCROLL") != nil,
                   let first = model.posts.first(where: { model.isFresh($0.pid) }) {
                    try? await Task.sleep(for: .milliseconds(60))
                    hooks.setVisiblePid(first.pid)
                }
            }
            if env("S1_PERF") != nil {
                await PostBodyCache.shared.reportAndReset("after-loadmore")
            }
        }

        // S1_JUMP_PAGE=<n> then S1_LOAD_EARLIER=<n> exercise jumping to a late
        // page and loading the replies above it.
        if let page = DebugHooks.int("S1_JUMP_PAGE") {
            await model.loadPage(page)
            // S1_TOP_ROW=1 parks the list one post down so the "load earlier"
            // row above the first post is on screen for a screenshot.
            let offset = env("S1_TOP_ROW") == "1" ? 1 : 0
            hooks.setVisiblePid(model.posts.dropFirst(offset).first?.pid)
            try? await Task.sleep(for: .milliseconds(600))
        }
        if let times = DebugHooks.int("S1_LOAD_EARLIER") {
            for _ in 0..<max(0, times) {
                try? await Task.sleep(for: .milliseconds(400))
                await hooks.loadEarlier(true)
            }
        }
        // S1_LOAD_EARLIER_GATED=<n> replays the scroll-triggered path, which
        // must load only the first page and then hold until the list moves.
        if let times = DebugHooks.int("S1_LOAD_EARLIER_GATED") {
            for _ in 0..<max(0, times) {
                try? await Task.sleep(for: .milliseconds(500))
                await hooks.loadEarlier(false)
            }
        }
        // S1_JUMP_SHEET=1 opens the page picker so its input field can be checked.
        if env("S1_JUMP_SHEET") == "1" {
            try? await Task.sleep(for: .milliseconds(1200))
            hooks.showPageJump()
        }
        if let pid = env("S1_SCROLL"), !pid.isEmpty {
            try? await Task.sleep(for: .milliseconds(300))
            hooks.setVisiblePid(pid)
        }
        if let raw = env("S1_VIEW_IMAGE"), let target = URL(string: raw) {
            try? await Task.sleep(for: .milliseconds(1200))
            hooks.openImage(target)
        }
        // S1_TOAST=<text> shows the toast so its look and timing can be filmed.
        if let text = env("S1_TOAST"), !text.isEmpty {
            try? await Task.sleep(for: .milliseconds(400))
            let hold = DebugHooks.int("S1_TOAST_HOLD") ?? 2200
            hooks.showToast(ToastMessage(text: text, style: .success, duration: .milliseconds(hold)))
        }
        // S1_INLINE_NOTICE=<text> forces the inline retry notice.
        if let text = env("S1_INLINE_NOTICE"), !text.isEmpty {
            model.errorMessage = text
        }
        // S1_QUOTE_TAP=<pid> follows a quote (the button turns into "back");
        // S1_QUOTE_BACK=1 then takes it, so both states can be filmed.
        if let pid = env("S1_QUOTE_TAP"), !pid.isEmpty {
            // Wait for the first page, otherwise there is no origin to return to.
            for _ in 0..<25 where model.posts.isEmpty {
                try? await Task.sleep(for: .milliseconds(200))
            }
            try? await Task.sleep(for: .milliseconds(600))
            await hooks.jump(pid, env("S1_QUOTE_FROM"))
            if env("S1_QUOTE_BACK") == "1" {
                try? await Task.sleep(for: .milliseconds(1800))
                hooks.returnToOrigin()
            }
        }
        // S1_CHECK_NEW=1 exercises the bottom pull without a gesture.
        if env("S1_CHECK_NEW") == "1" {
            try? await Task.sleep(for: .milliseconds(1500))
            let added = await model.refreshNewReplies()
            let addedText: String = added.map { String($0) } ?? "nil"
            let messageText: String = model.lastCheckMessage ?? "-"
            DebugHooks.log("S1_CHECK_NEW added=" + addedText + " message=" + messageText)
        }
        // S1_POP=1 pops back to the list so the tab bar's return can be filmed.
        if env("S1_POP") == "1" {
            try? await Task.sleep(for: .milliseconds(2500))
            hooks.dismiss()
        }
        // S1_CLEAR_IMAGES=1 drops this thread's cached pictures so the eviction
        // path can be checked without tapping the menu.
        if env("S1_CLEAR_IMAGES") == "1" {
            try? await Task.sleep(for: .milliseconds(1500))
            let before = await ImageLoader.shared.diskUsage()
            hooks.clearThreadImageCache()
            try? await Task.sleep(for: .milliseconds(800))
            let after = await ImageLoader.shared.diskUsage()
            DebugHooks.log("S1_CLEAR_IMAGES \(before) -> \(after)")
        }
    }
    #endif
}
