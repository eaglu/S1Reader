import XCTest
@testable import S1Reader

/// 骨架要按屏幕高度铺满：条数不是写死的三，也不能在矮屏上多到离谱。
final class ThreadSkeletonMetricsTests: XCTestCase {
    func testTallScreenIsCoveredWithSpareRows() {
        for height in [667.0, 844.0, 932.0, 1366.0] {
            let covered = CGFloat(ThreadSkeletonMetrics.rowCount(for: height))
                * ThreadSkeletonMetrics.rowHeight
            XCTAssertGreaterThanOrEqual(covered, height, "高度 \(height) 的屏幕底部会露白")
        }
    }

    func testShortScreensKeepTheMinimum() {
        XCTAssertEqual(ThreadSkeletonMetrics.rowCount(for: 0), ThreadSkeletonMetrics.minimumCount)
        XCTAssertEqual(ThreadSkeletonMetrics.rowCount(for: 100), ThreadSkeletonMetrics.minimumCount)
        XCTAssertEqual(ThreadSkeletonMetrics.rowCount(for: .nan), ThreadSkeletonMetrics.minimumCount)
    }

    func testCountGrowsWithTheScreen() {
        XCTAssertGreaterThan(
            ThreadSkeletonMetrics.rowCount(for: 932),
            ThreadSkeletonMetrics.rowCount(for: 667)
        )
    }
}
