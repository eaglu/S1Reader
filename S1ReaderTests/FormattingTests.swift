import XCTest
@testable import S1Reader

final class FormattingTests: XCTestCase {

    // MARK: - relative time

    func testJustNow() {
        XCTAssertEqual(Formatters.relative(Date()), "刚刚")
        XCTAssertEqual(Formatters.relative(Date().addingTimeInterval(-59)), "刚刚")
    }

    func testMinutesHoursDays() {
        XCTAssertEqual(Formatters.relative(Date().addingTimeInterval(-60)), "1 分钟前")
        XCTAssertEqual(Formatters.relative(Date().addingTimeInterval(-59 * 60)), "59 分钟前")
        XCTAssertEqual(Formatters.relative(Date().addingTimeInterval(-3600)), "1 小时前")
        XCTAssertEqual(Formatters.relative(Date().addingTimeInterval(-23 * 3600)), "23 小时前")
        XCTAssertEqual(Formatters.relative(Date().addingTimeInterval(-86_400)), "1 天前")
        XCTAssertEqual(Formatters.relative(Date().addingTimeInterval(-6 * 86_400)), "6 天前")
    }

    func testOlderThanAWeekUsesACalendarDate() {
        let date = Date().addingTimeInterval(-30 * 86_400)
        let text = Formatters.relative(date)
        XCTAssertTrue(text.contains("月") && text.contains("日"), "got \(text)")
        XCTAssertFalse(text.hasSuffix("前"))
    }

    func testFutureDateDoesNotReadAsANegativeInterval() {
        // Clock skew between device and server is common; "-3 小时前" must never
        // be shown.
        let text = Formatters.relative(Date().addingTimeInterval(3 * 3600))
        XCTAssertEqual(text, "刚刚")
    }

    func testServerDateRespectsShanghaiTime() {
        // Discuz prints server-local (UTC+8) timestamps regardless of the device
        // time zone; parsing must not shift them.
        let date = try? XCTUnwrap(Formatters.date(from: "2024-11-12 19:01"))
        XCTAssertNotNil(date)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date!)
        XCTAssertEqual(parts.year, 2024)
        XCTAssertEqual(parts.month, 11)
        XCTAssertEqual(parts.day, 12)
        XCTAssertEqual(parts.hour, 19)
        XCTAssertEqual(parts.minute, 1)
    }

    func testDateOnlyTimestampIsUnderstood() {
        // Thread lists sometimes carry "2024-11-12" with no time. Falling back to
        // the raw string is survivable, but the relative formatter is nicer.
        XCTAssertNotNil(Formatters.date(from: "2024-11-12"))
    }

    func testRelativePassesUnknownFormatsThrough() {
        XCTAssertEqual(Formatters.relative("昨天 21:33"), "昨天 21:33")
        XCTAssertEqual(Formatters.relative(""), "")
    }

    // MARK: - compactCount

    func testCompactCount() {
        XCTAssertEqual(Formatters.compactCount(0), "0")
        XCTAssertEqual(Formatters.compactCount(9_999), "9999")
        XCTAssertEqual(Formatters.compactCount(10_000), "1.0万")
        XCTAssertEqual(Formatters.compactCount(12_345), "1.2万")
        XCTAssertEqual(Formatters.compactCount(1_234_567), "123.5万")
    }

    // MARK: - flex decoding helpers

    private struct Holder: Decodable {
        let value: String
        enum CodingKeys: String, CodingKey { case value }
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            value = container.flexString(.value)
        }
    }

    private struct IntHolder: Decodable {
        let value: Int
        enum CodingKeys: String, CodingKey { case value }
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            value = container.flexInt(.value)
        }
    }

    private struct BoolHolder: Decodable {
        let value: Bool
        enum CodingKeys: String, CodingKey { case value }
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            value = container.flexBool(.value)
        }
    }

    func testFlexStringAcceptsStringsNumbersAndBooleans() throws {
        XCTAssertEqual(try decode(Holder.self, #"{"value": "a"}"#).value, "a")
        XCTAssertEqual(try decode(Holder.self, #"{"value": 42}"#).value, "42")
        XCTAssertEqual(try decode(Holder.self, #"{"value": 42.9}"#).value, "42")
        XCTAssertEqual(try decode(Holder.self, #"{"value": true}"#).value, "1")
    }

    func testFlexStringSurvivesNestedObject() throws {
        XCTAssertEqual(try decode(Holder.self, #"{"value": {"a": 1}}"#).value, "")
    }

    func testFlexInt() throws {
        XCTAssertEqual(try decode(IntHolder.self, #"{"value": "41"}"#).value, 41)
        XCTAssertEqual(try decode(IntHolder.self, #"{"value": 41}"#).value, 41)
        XCTAssertEqual(try decode(IntHolder.self, #"{"value": "abc"}"#).value, 0)
        XCTAssertEqual(try decode(IntHolder.self, #"{"value": "41.9"}"#).value, 0)
    }

    func testFlexIntOnOverflowingCount() throws {
        // A thread with a reply count past Int64 (Discuz has been seen emitting
        // junk) must clamp, not crash the whole page decode.
        XCTAssertEqual(try decode(IntHolder.self, #"{"value": "99999999999999999999999"}"#).value, 0)
    }

    func testFlexBool() throws {
        for (raw, expected) in [("\"1\"", true), ("1", true), ("\"true\"", true), ("\"TRUE\"", true),
                                ("\"0\"", false), ("0", false), ("\"\"", false), ("null", false)] {
            let json = "{\"value\": \(raw)}"
            XCTAssertEqual(try decode(BoolHolder.self, json).value, expected, json)
        }
    }

    // MARK: - AvatarURL

    func testAvatarURLFromUID() {
        XCTAssertEqual(
            AvatarURL.url(uid: "464256")?.absoluteString,
            "https://avatar.stage1st.com/000/46/42/56_avatar_middle.jpg"
        )
    }

    func testAvatarURLRejectsNonNumericUID() {
        XCTAssertNil(AvatarURL.url(uid: ""))
        XCTAssertNil(AvatarURL.url(uid: "abc"))
    }
}
