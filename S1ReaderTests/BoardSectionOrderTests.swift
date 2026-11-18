import XCTest
@testable import S1Reader

/// 主论坛 must be shown ahead of 热门新区 no matter which order the server
/// returns them in. Everything else keeps the server's order.
@MainActor
final class BoardSectionOrderTests: XCTestCase {
    // MARK: - Fixtures

    /// Builds categories the way the index response does, so the name gets the
    /// same HTML-entity pass the real payload gets.
    private func categories(_ entries: [(name: String, fids: [String])]) throws -> [ForumCategory] {
        let payload = entries.enumerated().map { index, entry in
            """
            {"fid":"\(index + 1)","name":"\(entry.name)","forums":\(jsonArray(entry.fids))}
            """
        }
        let json = "[\(payload.joined(separator: ","))]"
        return try JSONDecoder().decode([ForumCategory].self, from: Data(json.utf8))
    }

    private func jsonArray(_ values: [String]) -> String {
        "[" + values.map { "\"\($0)\"" }.joined(separator: ",") + "]"
    }

    private func forums(_ fids: [String]) -> [Forum] {
        fids.map { Forum(fid: $0, name: "板块\($0)") }
    }

    private func model(_ entries: [(name: String, fids: [String])]) throws -> AppModel {
        let model = AppModel()
        model.categories = try categories(entries)
        model.forums = forums(entries.flatMap(\.fids))
        return model
    }

    // MARK: - Reordering

    func testMainForumIsMovedAheadOfHotZone() throws {
        let model = try model([
            ("热门新区", ["10"]),
            ("主论坛", ["20"]),
            ("其他", ["30"]),
        ])

        XCTAssertEqual(model.sections.map(\.title), ["主论坛", "热门新区", "其他"])
        XCTAssertEqual(model.sections.map(\.id), ["2", "1", "3"])
    }

    func testOrderIsUnchangedWhenMainForumIsAlreadyFirst() throws {
        let model = try model([
            ("主论坛", ["20"]),
            ("热门新区", ["10"]),
            ("其他", ["30"]),
        ])

        XCTAssertEqual(model.sections.map(\.title), ["主论坛", "热门新区", "其他"])
    }

    /// A third section between the two must not be dragged along: only 主论坛
    /// moves, so the rest of the server order survives untouched.
    func testUnrelatedSectionsKeepTheServerOrder() throws {
        let model = try model([
            ("热门新区", ["10"]),
            ("资源区", ["40"]),
            ("主论坛", ["20"]),
            ("其他", ["30"]),
        ])

        XCTAssertEqual(model.sections.map(\.title), ["主论坛", "热门新区", "资源区", "其他"])
    }

    /// Names with stray spacing, a full-width space or a suffix still match.
    func testNamesAreMatchedLoosely() throws {
        let model = try model([
            ("热门新区（子版）", ["10"]),
            (" 主 论坛 ", ["20"]),
        ])

        XCTAssertEqual(model.sections.map(\.title), [" 主 论坛 ", "热门新区（子版）"])
    }

    // MARK: - No-op paths

    func testOrderIsUntouchedWhenNeitherNameIsPresent() throws {
        let model = try model([
            ("资源区", ["40"]),
            ("站务", ["50"]),
        ])

        XCTAssertEqual(model.sections.map(\.title), ["资源区", "站务"])
        XCTAssertEqual(model.sections.map(\.id), ["1", "2"])
    }

    /// A renamed 热门新区 leaves 主论坛 where the server put it rather than
    /// hoisting it to the top.
    func testRenamedHotZoneLeavesOrderAlone() throws {
        let model = try model([
            ("新区预告", ["10"]),
            ("主论坛", ["20"]),
        ])

        XCTAssertEqual(model.sections.map(\.title), ["新区预告", "主论坛"])
    }

    func testMissingMainForumLeavesOrderAlone() throws {
        let model = try model([
            ("热门新区", ["10"]),
            ("站务", ["50"]),
        ])

        XCTAssertEqual(model.sections.map(\.title), ["热门新区", "站务"])
    }

    // MARK: - Intra-section order

    /// Forums inside a category keep whatever order the server listed them in;
    /// the pin only moves whole sections.
    func testForumOrderInsideASectionIsPreserved() throws {
        let model = try model([
            ("热门新区", ["10"]),
            ("主论坛", ["20", "21", "22"]),
        ])

        XCTAssertEqual(model.sections.first?.forums.map(\.fid), ["20", "21", "22"])
        XCTAssertEqual(model.sections.last?.forums.map(\.fid), ["10"])
    }

    func testLeftoverBoardsStayInTheTrailingOtherSection() throws {
        let model = try model([("热门新区", ["10"]), ("主论坛", ["20"])])
        model.forums.append(Forum(fid: "99", name: "未分组"))

        XCTAssertEqual(model.sections.map(\.title), ["主论坛", "热门新区", "其他"])
        XCTAssertEqual(model.sections.last?.forums.map(\.fid), ["99"])
    }
}
