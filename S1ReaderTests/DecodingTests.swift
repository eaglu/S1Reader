import XCTest
@testable import S1Reader

/// Discuz! is inconsistent about JSON types; these tests pin down what the
/// decoders must accept, using shapes the mobile API actually produces.
final class DecodingTests: XCTestCase {

    // MARK: - Member

    func testMemberWithStringNumbers() throws {
        let member = try decode(Member.self, """
        {
          "member_uid": "464256",
          "member_username": "Faye",
          "member_avatar": "https://avatar.stage1st.com/000/46/42/56_avatar_middle.jpg",
          "formhash": "ab12cd34",
          "readaccess": "1",
          "group": {"grouptitle": "管理员"},
          "notice": {"newprompt": "3", "newpm": "1"}
        }
        """)
        XCTAssertEqual(member.uid, "464256")
        XCTAssertTrue(member.isLoggedIn)
        XCTAssertEqual(member.groupTitle, "管理员")
        XCTAssertEqual(member.unreadNotices, 3)
        XCTAssertNotNil(member.avatarURL)
    }

    func testMemberWithNumericNoticeCount() throws {
        // Discuz sends newprompt as a number on some boards; the badge must not
        // silently disappear.
        let member = try decode(Member.self, """
        {"member_uid": "1", "member_username": "a", "notice": {"newprompt": 7}}
        """)
        XCTAssertEqual(member.unreadNotices, 7)
    }

    func testGuestMember() throws {
        let member = try decode(Member.self, #"{"member_uid": "0", "member_username": ""}"#)
        XCTAssertFalse(member.isLoggedIn)
        XCTAssertEqual(member.unreadNotices, 0)
    }

    func testMemberWithoutNoticeBlock() throws {
        let member = try decode(Member.self, #"{"member_uid": "5", "member_username": "b"}"#)
        XCTAssertEqual(member.unreadNotices, 0)
        XCTAssertNil(member.formhash)
    }

    func testMalformedMemberFallsBackToDefaults() throws {
        let member = try decode(Member.self, #"{"member_uid": {"nested": true}}"#)
        XCTAssertEqual(member.uid, "")
        XCTAssertFalse(member.isLoggedIn)
    }

    // MARK: - ThreadSummary

    func testThreadSummaryFields() throws {
        let thread = try decode(ThreadSummary.self, """
        {
          "tid": "2291277",
          "subject": "标题 &amp; 副标题",
          "author": "{{PERSON_t5idz8rc}}",
          "authorid": "123",
          "replies": "3380",
          "views": 45678,
          "lastpost": "1700000000",
          "lastposter": "最后回复",
          "displayorder": "1",
          "digest": "1",
          "attachment": "2"
        }
        """)
        XCTAssertEqual(thread.tid, "2291277")
        XCTAssertEqual(thread.subject, "标题 & 副标题")
        XCTAssertEqual(thread.replies, 3380)
        XCTAssertEqual(thread.views, 45678)
        XCTAssertTrue(thread.isPinned)
        XCTAssertTrue(thread.isDigest)
        XCTAssertTrue(thread.hasAttachment)
    }

    func testThreadSummaryIsNotPinnedByDefault() throws {
        let thread = try decode(ThreadSummary.self, #"{"tid": "1", "subject": "s"}"#)
        XCTAssertFalse(thread.isPinned)
        XCTAssertFalse(thread.hasAttachment)
        XCTAssertEqual(thread.replies, 0)
        XCTAssertNil(thread.previewImageURL)
    }

    func testThreadSummaryWithFloatReplyCount() throws {
        // JSON numbers decoded as Double must not turn into "3380.0".
        let thread = try decode(ThreadSummary.self, #"{"tid": "1", "subject": "s", "replies": 3380.0}"#)
        XCTAssertEqual(thread.replies, 3380)
    }

    func testThreadSummaryRemotePreview() throws {
        let thread = try decode(ThreadSummary.self, """
        {"tid": "1", "subject": "s", "attachmentImagePreviewList": [
          {"attachment": "https://example.com/a.jpg", "remote": "1"}
        ]}
        """)
        XCTAssertEqual(thread.previewImageURL, URL(string: "https://example.com/a.jpg"))
    }

    func testThreadSummaryLocalPreview() throws {
        let thread = try decode(ThreadSummary.self, """
        {"tid": "1", "subject": "s", "attachmentImagePreviewList": [
          {"attachment": "202401/01/abc.jpg", "remote": "0"}
        ]}
        """)
        XCTAssertEqual(
            thread.previewImageURL,
            URL(string: "https://stage1st.com/2b/data/attachment/forum/202401/01/abc.jpg")
        )
    }

    func testThreadSummaryPreviewWithFullPathIsNotDoubled() throws {
        // The listing sometimes already includes the "forum/" segment.
        let thread = try decode(ThreadSummary.self, """
        {"tid": "1", "subject": "s", "attachmentImagePreviewList": [
          {"attachment": "forum/202401/01/abc.jpg", "remote": "0"}
        ]}
        """)
        XCTAssertEqual(thread.previewImageURL?.absoluteString.components(separatedBy: "/forum/").count, 2)
    }

    // MARK: - Post

    func testPostPosition() throws {
        let post = try decode(Post.self, #"{"pid": "1", "tid": "2", "position": "41"}"#)
        XCTAssertEqual(post.position, 41)
    }

    func testPostPositionFallsBackToNumber() throws {
        let post = try decode(Post.self, #"{"pid": "1", "tid": "2", "number": "41"}"#)
        XCTAssertEqual(post.position, 41)
    }

    func testPostFirstFloorFlag() throws {
        XCTAssertTrue(try decode(Post.self, #"{"pid": "1", "tid": "2", "first": 1}"#).isFirst)
        XCTAssertTrue(try decode(Post.self, #"{"pid": "1", "tid": "2", "first": "1"}"#).isFirst)
        XCTAssertFalse(try decode(Post.self, #"{"pid": "1", "tid": "2"}"#).isFirst)
    }

    func testPostAdminFlag() throws {
        XCTAssertTrue(try decode(Post.self, #"{"pid": "1", "tid": "2", "adminid": "1"}"#).isAdmin)
        XCTAssertFalse(try decode(Post.self, #"{"pid": "1", "tid": "2", "adminid": "0"}"#).isAdmin)
    }

    // MARK: - Pages

    func testThreadPage() throws {
        let page = try decode(ThreadPage.self, """
        {
          "ppp": "40",
          "thread": {"tid": "2", "subject": "标题", "replies": "41", "views": "10", "author": "a", "dateline": "d", "closed": "0"},
          "postlist": [
            {"pid": "10", "tid": "2", "position": "1"},
            {"pid": "11", "tid": "2", "position": "2"}
          ]
        }
        """)
        XCTAssertEqual(page.perPage, 40)
        XCTAssertEqual(page.posts.count, 2)
        XCTAssertEqual(page.thread?.subject, "标题")
        XCTAssertEqual(page.thread?.replies, 41)
        XCTAssertEqual(page.thread?.isClosed, false)
    }

    func testEmptyThreadPageKeepsGoing() throws {
        let page = try decode(ThreadPage.self, #"{"postlist": []}"#)
        XCTAssertTrue(page.posts.isEmpty)
        XCTAssertNil(page.thread)
        XCTAssertEqual(page.perPage, 1, "a missing ppp must not divide by zero later")
    }

    func testThreadListPage() throws {
        let page = try decode(ThreadListPage.self, """
        {
          "page": "2",
          "tpp": "50",
          "forum": {"name": "动漫", "description": "说动画", "threads": "1200"},
          "forum_threadlist": [{"tid": "9", "subject": "帖"}]
        }
        """)
        XCTAssertEqual(page.forumName, "动漫")
        XCTAssertEqual(page.description, "说动画")
        XCTAssertEqual(page.totalThreads, 1200)
        XCTAssertEqual(page.page, 2)
        XCTAssertEqual(page.perPage, 50)
        XCTAssertEqual(page.threads.map(\.tid), ["9"])
    }

    func testThreadListPageWithNoPageNumbers() throws {
        let page = try decode(ThreadListPage.self, #"{"forum_threadlist": []}"#)
        XCTAssertEqual(page.page, 1)
        XCTAssertEqual(page.perPage, 1)
        XCTAssertTrue(page.threads.isEmpty)
    }

    // MARK: - Forums

    func testForumIndexWithSubforums() throws {
        let index = try decode(ForumIndex.self, """
        {
          "forumlist": [
            {"fid": "6", "name": "动漫", "description": "d", "threads": "1", "posts": "2", "todayposts": "3",
             "sublist": [{"fid": "60", "name": "子版"}]}
          ],
          "catlist": [{"fid": "1", "name": "分类", "forums": ["6", "60"]}]
        }
        """)
        XCTAssertEqual(index.forums.count, 1)
        XCTAssertEqual(index.forums[0].subforums.first?.name, "子版")
        XCTAssertEqual(index.categories.first?.forumIDs, ["6", "60"])
    }

    func testBrokenForumListIsEmptyNotFatal() throws {
        let index = try decode(ForumIndex.self, #"{"forumlist": "unexpected"}"#)
        XCTAssertTrue(index.forums.isEmpty)
        XCTAssertTrue(index.categories.isEmpty)
    }

    // MARK: - Envelope

    func testEnvelopeWithMessageOnly() throws {
        let envelope = try decode(APIEnvelope<Member>.self, """
        {"Message": {"messageval": "to_login", "messagestr": "请先登录"}}
        """)
        XCTAssertNil(envelope.variables)
        XCTAssertEqual(envelope.message?.value, "to_login")
    }

    func testReplyResultAcceptsNumericPid() throws {
        let result = try decode(APIClient.ReplyResult.self, #"{"pid": 12345}"#)
        XCTAssertEqual(result.pid, "12345")
    }

    // MARK: - Form encoding

    func testFormEncodingEscapesWhatWouldBreakTheBody() {
        let body = String(decoding: APIClient.formEncode([
            "message": "你好 & plus+ 50%",
            "formhash": "ab12cd34"
        ]), as: UTF8.self)
        // Order is not guaranteed, so check the encoded pair, not the string.
        let parts = Set(body.split(separator: "&").map(String.init))
        XCTAssertEqual(parts, [
            "message=%E4%BD%A0%E5%A5%BD%20%26%20plus%2B%2050%25",
            "formhash=ab12cd34"
        ])
    }

    func testFormEncodingLeavesUnreservedCharacters() {
        XCTAssertEqual(String(data: APIClient.formEncode(["a": "x-y_z.~9"]), encoding: .utf8), "a=x-y_z.~9")
    }
}
