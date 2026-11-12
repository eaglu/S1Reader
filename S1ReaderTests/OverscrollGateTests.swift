import XCTest
@testable import S1Reader

/// 触顶闸门：一次上拉只放一次，回顶之后才重新打开。
final class OverscrollGateTests: XCTestCase {
    func testAPullPastTheTopFiresOnce() {
        var gate = OverscrollGate()
        // 橡皮筋回弹期间 offset 会一直停在触发线以下。
        let fired = fireOffsets(
            [-60, -70, -90, -120, -160, -200, -260, -300, -273, -190, -140],
            gate: &gate
        )
        XCTAssertEqual(fired, [-60])
        XCTAssertEqual(gate.firedCount, 1)
    }

    func testTheGateStaysClosedUntilTheListComesBackAboveTheResetLine() {
        var gate = OverscrollGate()
        // 加载完仍停在顶部下方（prepend 还没把内容撑起来），再触顶也不放行。
        let fired = fireOffsets([-60, -116, -120, -300, -60], gate: &gate)
        XCTAssertEqual(fired, [-60])

        // 真正回到顶部，下一次上拉才是新的一次触顶。
        XCTAssertFalse(gate.update(offset: -5), "回顶不该触发加载")
        XCTAssertEqual(fireOffsets([-40, -80], gate: &gate), [-80])
        XCTAssertEqual(gate.firedCount, 2)
    }

    func testOffsetsInsideTheContentNeverFire() {
        var gate = OverscrollGate()
        let fired = fireOffsets([0, 40, -9, -10, -54, 0, -9], gate: &gate)
        XCTAssertEqual(fired, [])
        XCTAssertEqual(gate.firedCount, 0)
    }

    func testTheTriggerAndResetLinesDecideTheEdges() {
        var gate = OverscrollGate(trigger: -55, reset: -10)
        XCTAssertFalse(gate.update(offset: -55), "刚好在触发线上还不算触顶")
        XCTAssertTrue(gate.update(offset: -56))
        XCTAssertFalse(gate.update(offset: -10), "刚好在回位线上还不算回顶")
        XCTAssertFalse(gate.update(offset: -56), "没回到 -10 以上，闸门还是关的")
        XCTAssertFalse(gate.update(offset: -9))
        XCTAssertTrue(gate.update(offset: -56))
    }

    func testRearmOpensTheGateWithoutAnOffsetChange() {
        var gate = OverscrollGate()
        XCTAssertTrue(gate.update(offset: -80))
        XCTAssertFalse(gate.update(offset: -80))
        gate.rearm()
        XCTAssertTrue(gate.update(offset: -80))
    }

    private func fireOffsets(_ offsets: [CGFloat], gate: inout OverscrollGate) -> [CGFloat] {
        var fired: [CGFloat] = []
        for offset in offsets where gate.update(offset: offset) {
            fired.append(offset)
        }
        return fired
    }
}
