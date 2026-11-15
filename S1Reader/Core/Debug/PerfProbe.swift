import QuartzCore
import SwiftUI
import UIKit

/// Scroll-time probe for the thread screen: how long frames take, how many
/// frames are late, and how much work the list does while it moves.
///
/// It is compiled into every configuration, because a Release build is the only
/// one worth measuring — `-Onone` inflates every body and every attributed
/// string and would flatter any change. It does nothing unless
/// `S1_PERF_SCROLL=1` is in the launch environment, which an App Store launch
/// never sets: every counter is an integer increment behind one `Bool`.
///
/// The run is one script, identical before and after an optimisation: find the
/// thread's scroll view, drag it down and back a fixed distance at a fixed
/// speed, and measure the frames produced while it moves. The numbers land on
/// stdout and in `s1-perf-scroll.log` inside the app's tmp directory.
@MainActor
enum PerfProbe {
    static let isEnabled = ProcessInfo.processInfo.environment["S1_PERF_SCROLL"] != nil
    /// `S1_PERF_THREAD=2206666` opens that thread without the DEBUG-only
    /// `S1_OPEN` hook, so a Release build can be measured on the same screen.
    static let threadID = ProcessInfo.processInfo.environment["S1_PERF_THREAD"]

    /// Script shape: `S1_PERF_TRAVEL` points per leg, `S1_PERF_SPEED` points per
    /// second, `S1_PERF_CYCLES` down-and-back pairs.
    private static var travel: CGFloat { env("S1_PERF_TRAVEL").flatMap { Double($0) }.map { CGFloat($0) } ?? 2400 }
    private static var speed: CGFloat { env("S1_PERF_SPEED").flatMap { Double($0) }.map { CGFloat($0) } ?? 700 }
    private static var cycles: Int { env("S1_PERF_CYCLES").flatMap { Int($0) } ?? 2 }
    /// Waits this long after the page lands before scrolling, so a run can be
    /// made with the arrival work (pre-parse, image probes) already finished.
    private static var delay: Int { env("S1_PERF_DELAY").flatMap { Int($0) } ?? 0 }

    private static func env(_ key: String) -> String? {
        #if DEBUG
        ProcessInfo.processInfo.environment[key]
        #else
        // `S1_PERF_SCROLL` itself is read above in both configurations; the fine
        // tuning knobs only matter when someone is already measuring a Debug
        // build by hand.
        ProcessInfo.processInfo.environment[key]
        #endif
    }

    private static let outputURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("s1-perf-scroll.log")

    // MARK: - Counters

    /// What the list did, not how long it took. One struct so a run prints one
    /// aligned line that can be diffed against another run.
    struct Counts {
        var listBodies = 0
        var rowsBuilt = 0
        var rowBodies = 0
        var rowHeaders = 0
        var contentBodies = 0
        var blockBuilds = 0
        var textConcatenations = 0
        var filterRuns = 0
        var filterPosts = 0
        var avatarBodies = 0
        var mirrorHits = 0
        var mirrorMisses = 0
        var cacheLookups = 0
        var cacheParses = 0
        /// Writes to `@State` that redraw the whole list while it scrolls.
        var scrollOffsetWrites = 0
        var visiblePidWrites = 0
        /// Row bodies per floor, so a floor that rebuilds on every pass is
        /// visible instead of being averaged away.
        var rowBodiesByPid: [String: Int] = [:]
    }

    static var counts = Counts()

    /// Wall time spent building the views themselves, in milliseconds.
    static var rowBodyMs = 0.0
    static var contentBodyMs = 0.0
    static var blockBuildMs = 0.0
    static var headerMs = 0.0
    static var avatarBodyMs = 0.0

    static var totalMeasuredMs: Double {
        rowBodyMs + headerMs + avatarBodyMs
    }

    enum Stopwatch {
        case rowBody
        case contentBody
        case blocks
        case header
        case avatar
    }

    /// Runs `make` when the probe is on and returns it untouched when it is not.
    @inline(__always)
    static func measured<T>(_ kind: Stopwatch, _ make: () -> T) -> T {
        guard isEnabled else { return make() }
        let start = CACurrentMediaTime()
        let value = make()
        record(kind, (CACurrentMediaTime() - start) * 1000)
        return value
    }

    private static func record(_ kind: Stopwatch, _ ms: Double) {
        switch kind {
        case .rowBody: rowBodyMs += ms
        case .contentBody: contentBodyMs += ms
        case .blocks: blockBuildMs += ms
        case .header: headerMs += ms
        case .avatar: avatarBodyMs += ms
        }
    }

    /// Temporary switch for an A/B run: only ever true while `S1_PERF_SCROLL`
    /// is set, so a diagnostic never changes how the app behaves for a reader.
    static func diagnostic(_ key: String) -> Bool {
        guard isEnabled else { return false }
        guard let value = ProcessInfo.processInfo.environment[key] else { return false }
        return !value.isEmpty
    }

    /// Called from a body; does nothing at all unless a measurement is running.
    @inline(__always)
    static func note(_ update: (inout Counts) -> Void) {
        guard isEnabled else { return }
        update(&counts)
    }

    // MARK: - Frame sampling

    /// Frame-to-frame intervals of the display link. A frame that arrives two
    /// vsyncs late is a hitch; skipping a callback entirely shows up as a
    /// doubled interval, which is what "dropped frames" counts.
    @MainActor
    private final class Sampler {
        private(set) var intervals: [Double] = []
        /// Seconds into the script at which a frame arrived late.
        private(set) var hitchOffsets: [Double] = []
        private(set) var measuredPerFrame: [Double] = []
        private(set) var nominal: Double = 0
        private var lastTimestamp: Double = 0
        private var startTimestamp: Double = 0
        private var lastMeasured: Double = 0
        private var link: CADisplayLink?

        func start() {
            intervals.removeAll()
            hitchOffsets.removeAll()
            measuredPerFrame.removeAll()
            lastTimestamp = 0
            startTimestamp = CACurrentMediaTime()
            lastMeasured = PerfProbe.totalMeasuredMs
            let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
            link.add(to: .main, forMode: .common)
            self.link = link
        }

        func stop() {
            link?.invalidate()
            link = nil
        }

        @objc private func tick(_ link: CADisplayLink) {
            let expected = link.targetTimestamp - link.timestamp
            if expected > 0 { nominal = expected * 1000 }
            let now = link.timestamp
            if lastTimestamp > 0 {
                let interval = (now - lastTimestamp) * 1000
                intervals.append(interval)
                if interval > max(nominal, 16.67) * 1.5 {
                    hitchOffsets.append(now - startTimestamp)
                }
                let measured = PerfProbe.totalMeasuredMs
                measuredPerFrame.append(measured - lastMeasured)
                lastMeasured = measured
            } else {
                lastMeasured = PerfProbe.totalMeasuredMs
            }
            lastTimestamp = now
        }
    }

    /// Moves the scroll view one small step per frame, the way a finger does:
    /// the list has to lay out every row it passes, and the geometry callback
    /// fires on each frame.
    @MainActor
    private final class OffsetDriver {
        private let scrollView: UIScrollView
        private let travel: CGFloat
        private let speed: CGFloat
        private let legs: Int
        private let done: () -> Void
        private var link: CADisplayLink?
        private var lastTimestamp: Double = 0
        private var origin: CGFloat = 0
        private var direction: CGFloat = 1
        private var legsFinished = 0

        init(scrollView: UIScrollView, travel: CGFloat, speed: CGFloat, cycles: Int, done: @escaping () -> Void) {
            self.scrollView = scrollView
            self.travel = travel
            self.speed = speed
            self.legs = max(2, cycles * 2)
            self.done = done
        }

        func start() {
            origin = scrollView.contentOffset.y
            let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
            link.add(to: .main, forMode: .common)
            self.link = link
        }

        private var upperBound: CGFloat {
            let maxOffset = scrollView.contentSize.height
                - scrollView.bounds.height
                + scrollView.adjustedContentInset.bottom
            return max(maxOffset, origin + 1)
        }

        @objc private func tick(_ link: CADisplayLink) {
            let dt = lastTimestamp > 0 ? link.timestamp - lastTimestamp : link.targetTimestamp - link.timestamp
            lastTimestamp = link.timestamp
            guard dt > 0, dt < 0.25 else { return }

            var y = scrollView.contentOffset.y + direction * speed * CGFloat(dt)
            let ceiling = min(origin + travel, upperBound)
            if y >= ceiling {
                y = ceiling
                direction = -1
                legsFinished += 1
            } else if y <= origin {
                y = origin
                direction = 1
                legsFinished += 1
            }
            scrollView.contentOffset = CGPoint(x: scrollView.contentOffset.x, y: y)

            if legsFinished >= legs {
                link.invalidate()
                self.link = nil
                done()
            }
        }
    }

    // MARK: - Script

    /// Runs the scroll script once per launch. Cheap no-op when the probe is off.
    static func runScrollScriptIfEnabled() async {
        guard isEnabled else { return }
        guard !didRun else { return }
        didRun = true
        try? FileManager.default.removeItem(at: outputURL)
        guard await waitForContent() else {
            emit("S1_PERF_SCROLL aborted: the list never grew to a scrollable height")
            return
        }
        guard let scrollView = findScrollView() else {
            emit("S1_PERF_SCROLL aborted: no scroll view found")
            return
        }

        if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
        let sampler = Sampler()
        sampler.start()
        let started = CACurrentMediaTime()
        await drive(scrollView)
        let elapsed = (CACurrentMediaTime() - started) * 1000
        sampler.stop()

        emitSummary(sampler, scrollView: scrollView, elapsed: elapsed)
        reset()
    }

    private static var didRun = false

    private static func drive(_ scrollView: UIScrollView) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let driver = OffsetDriver(
                scrollView: scrollView,
                travel: travel,
                speed: speed,
                cycles: cycles
            ) { continuation.resume() }
            driver.start()
            // Keep the driver alive for the duration of the script.
            retainedDriver = driver
        }
        retainedDriver = nil
    }

    private static var retainedDriver: OffsetDriver?

    /// The thread list only becomes worth measuring once a page is in it.
    private static func waitForContent() async -> Bool {
        for _ in 0..<300 {
            if let scrollView = findScrollView(),
               scrollView.contentSize.height > scrollView.bounds.height * 1.5,
               scrollView.bounds.height > 200 {
                return true
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return false
    }

    /// The thread screen's own scroll view: the tallest visible one that has
    /// more content than fits. Navigation chrome is short and never qualifies.
    private static func findScrollView() -> UIScrollView? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        var best: (area: CGFloat, view: UIScrollView)?
        for window in windows where !window.isHidden {
            for candidate in scrollViews(in: window) {
                guard candidate.alpha > 0,
                      !candidate.isHidden,
                      candidate.bounds.height > 200,
                      candidate.contentSize.height > candidate.bounds.height * 1.5,
                      !(candidate is UITextView) else { continue }
                let area = candidate.bounds.width * candidate.bounds.height
                if best == nil || area > best!.area {
                    best = (area, candidate)
                }
            }
        }
        return best?.view
    }

    private static func scrollViews(in view: UIView) -> [UIScrollView] {
        var found: [UIScrollView] = []
        if let scrollView = view as? UIScrollView { found.append(scrollView) }
        for subview in view.subviews {
            found.append(contentsOf: scrollViews(in: subview))
        }
        return found
    }

    // MARK: - Reporting

    private static func emitSummary(_ sampler: Sampler, scrollView: UIScrollView, elapsed: Double) {
        let background = SharedPerfCounters.shared.drain()
        counts.cacheLookups += background[.cacheLookups] ?? 0
        counts.cacheParses += background[.cacheParses] ?? 0
        let intervals = sampler.intervals.sorted()
        guard !intervals.isEmpty else {
            emit("S1_PERF_SCROLL aborted: no frames observed")
            return
        }
        let vsync = sampler.nominal > 0 ? sampler.nominal : 16.67
        let count = intervals.count
        let mean = intervals.reduce(0, +) / Double(count)
        let hitchThreshold = vsync * 1.5
        let hitches = intervals.filter { $0 > hitchThreshold }
        let hitchTime = hitches.reduce(0, +) - Double(hitches.count) * vsync
        let dropped = intervals.reduce(0) { total, interval in
            total + max(0, Int((interval / vsync).rounded()) - 1)
        }
        let busy = sampler.measuredPerFrame.sorted()
        let busyMean = busy.isEmpty ? 0 : busy.reduce(0, +) / Double(count)

        emit("S1_PERF_SCROLL frames=\(count) vsync=\(f(vsync))ms elapsed=\(f(elapsed))ms"
            + " offset=\(Int(scrollView.contentOffset.y)) content=\(Int(scrollView.contentSize.height))")
        emit("S1_PERF_SCROLL frame_ms mean=\(f(mean)) p50=\(f(percentile(intervals, 0.5)))"
            + " p95=\(f(percentile(intervals, 0.95))) p99=\(f(percentile(intervals, 0.99)))"
            + " max=\(f(intervals.last ?? 0))")
        emit("S1_PERF_SCROLL hitches=\(hitches.count) (>\(f(hitchThreshold))ms)"
            + " hitchRatio=\(f(hitchTime / elapsed * 100))% droppedFrames=\(dropped)"
            + " smoothPct=\(f(Double(count - hitches.count) / Double(count) * 100))%")
        emit("S1_PERF_SCROLL body_ms_per_frame mean=\(f(busyMean))"
            + " p95=\(f(percentile(busy, 0.95)))")
        emit("S1_PERF_SCROLL hitch_at_s=" + sampler.hitchOffsets.map { f($0) }.joined(separator: ","))
        let rebuilt = counts.rowBodiesByPid.sorted { $0.value > $1.value }.prefix(6)
        emit("S1_PERF_SCROLL worst_rows="
            + rebuilt.map { "\($0.key):\($0.value)" }.joined(separator: " "))
        emit("S1_PERF_SCROLL counts listBodies=\(counts.listBodies) rowsBuilt=\(counts.rowsBuilt)"
            + " rowBodies=\(counts.rowBodies) headers=\(counts.rowHeaders)"
            + " contentBodies=\(counts.contentBodies) blockBuilds=\(counts.blockBuilds)"
            + " texts=\(counts.textConcatenations) filterRuns=\(counts.filterRuns)"
            + " filterPosts=\(counts.filterPosts) avatars=\(counts.avatarBodies)"
            + " mirrorHits=\(counts.mirrorHits) mirrorMisses=\(counts.mirrorMisses)"
            + " cacheLookups=\(counts.cacheLookups) cacheParses=\(counts.cacheParses)"
            + " scrollOffsetWrites=\(counts.scrollOffsetWrites)"
            + " visiblePidWrites=\(counts.visiblePidWrites)")
        emit("S1_PERF_SCROLL view_ms rowBody=\(f(rowBodyMs)) contentBody=\(f(contentBodyMs))"
            + " blocks=\(f(blockBuildMs)) headers=\(f(headerMs)) avatars=\(f(avatarBodyMs))")
    }

    private static func reset() {
        counts = Counts()
        rowBodyMs = 0
        contentBodyMs = 0
        blockBuildMs = 0
        headerMs = 0
        avatarBodyMs = 0
    }

    private static func percentile(_ sorted: [Double], _ fraction: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let index = min(sorted.count - 1, max(0, Int((Double(sorted.count - 1) * fraction).rounded())))
        return sorted[index]
    }

    private static func f(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    static func emit(_ line: String) {
        print(line)
        let data = Data((line + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: outputURL) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: outputURL)
        }
    }
}

/// Counters that the parsing actor writes as well as the main actor, so they
/// sit behind a lock instead of the main-actor isolation of `PerfProbe`.
final class SharedPerfCounters: @unchecked Sendable {
    static let shared = SharedPerfCounters()

    enum Key {
        case cacheLookups
        case cacheParses
    }

    private let lock = NSLock()
    private var values: [Key: Int] = [:]

    @inline(__always)
    func bump(_ key: Key) {
        guard PerfProbe.isEnabled else { return }
        lock.lock()
        values[key, default: 0] += 1
        lock.unlock()
    }

    func drain() -> [Key: Int] {
        lock.lock()
        let snapshot = values
        values.removeAll()
        lock.unlock()
        return snapshot
    }
}

extension View {
    /// Applies `transform` unless a diagnostic run asked for it off, keeping the
    /// view hierarchy (and therefore the measurement) unchanged otherwise.
    @ViewBuilder
    func unlessDiagnostic(_ key: String, _ transform: (Self) -> some View) -> some View {
        if PerfProbe.diagnostic(key) {
            self
        } else {
            transform(self)
        }
    }
}
