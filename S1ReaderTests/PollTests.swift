import XCTest
@testable import S1Reader

/// The poll Discuz hides in `special_poll`: every field is a string, options are
/// keyed by position, and a poll the app cannot read must never take the thread
/// down with it.
final class PollTests: XCTestCase {

    // MARK: - Options and numbers

    func testFourOptionsKeepServerOrderAndPercentages() throws {
        let poll = try decode(Poll.self, Self.fourOptions)

        XCTAssertEqual(poll.options.map(\.id), ["101", "102", "103", "104"])
        XCTAssertEqual(poll.options.map(\.text), ["选项 A", "选项 B", "选项 C", "选项 D"])
        XCTAssertEqual(poll.options.map(\.voters), [50, 20, 20, 10])
        XCTAssertEqual(poll.votersCount, 100)
        XCTAssertEqual(poll.voteCount, 100)
        XCTAssertFalse(poll.multiple)
        XCTAssertTrue(poll.allowsVoting)
        XCTAssertFalse(poll.isClosed(at: Self.now))
        XCTAssertNil(poll.options[3].color, "缺 color 的选项不该被塞一个假颜色")
    }

    func testMissingPercentIsRecomputedFromVotes() throws {
        // Some Discuz builds omit `percent`; a zero-width bar would make a real
        // option look untaken.
        let poll = try decode(Poll.self, """
        {
          "polloptions": {
            "1": {"polloptionid": "1", "polloption": "A", "votes": "3"},
            "2": {"polloptionid": "2", "polloption": "B", "votes": "1"}
          },
          "voterscount": "4", "multiple": "0", "maxchoices": "1",
          "allowvote": "1", "expirations": "0", "remaintime": ""
        }
        """)
        XCTAssertEqual(poll.options[0].percent, 75, accuracy: 0.001)
        XCTAssertEqual(poll.options[1].percent, 25, accuracy: 0.001)
    }

    func testOptionsAsArrayAreAccepted() throws {
        // S1 sends a dictionary, but the array shape exists on other Discuz
        // builds. Dropping the poll over that would be a silent regression.
        let poll = try decode(Poll.self, """
        {
          "polloptions": [
            {"polloptionid": "7", "polloption": "甲", "votes": "2", "percent": "66.67"},
            {"polloptionid": "8", "polloption": "乙", "votes": "1", "percent": "33.33"}
          ],
          "voterscount": "3", "multiple": "1", "maxchoices": "2",
          "allowvote": "1", "expirations": "0", "remaintime": ""
        }
        """)
        XCTAssertEqual(poll.options.map(\.id), ["7", "8"])
        XCTAssertTrue(poll.multiple)
        XCTAssertEqual(poll.maxChoices, 2)
    }

    func testOptionTextDropsEntitiesAndBBcode() throws {
        let poll = try decode(Poll.self, """
        {
          "polloptions": {
            "1": {"polloptionid": "1", "polloption": "[b]A &amp; B[/b] [url=x]链接[/url]", "votes": "1", "percent": "100"}
          },
          "voterscount": "1", "multiple": "0", "maxchoices": "1",
          "allowvote": "0", "expirations": "0", "remaintime": ""
        }
        """)
        XCTAssertEqual(poll.options[0].text, "A & B 链接")
    }

    func testNumericVotesAndFlagsAreAccepted() throws {
        // The decoder has to survive numbers where strings are usual.
        let poll = try decode(Poll.self, """
        {
          "polloptions": {"1": {"polloptionid": 11, "polloption": "A", "votes": 4, "percent": 40}},
          "voterscount": 10, "multiple": 1, "maxchoices": 3,
          "allowvote": 1, "expirations": 0, "remaintime": ""
        }
        """)
        XCTAssertEqual(poll.options[0].id, "11")
        XCTAssertEqual(poll.options[0].voters, 4)
        XCTAssertEqual(poll.votersCount, 10)
        XCTAssertTrue(poll.multiple)
        XCTAssertTrue(poll.allowsVoting)
    }

    // MARK: - Open / closed

    func testRollingSentinelIsNotADeadline() throws {
        // For a poll with no deadline Discuz sends `now + 86400` on every
        // request. Reading that as a real expiry would claim every open poll
        // closes tomorrow.
        let poll = try decode(Poll.self, Self.json(
            allowvote: "1",
            expirations: String(Int(Date().timeIntervalSince1970) + 86_400)
        ))
        XCTAssertFalse(poll.hasDeadline)
        XCTAssertFalse(poll.isClosed(at: Self.now))
        XCTAssertFalse(poll.isClosed(at: Self.now.addingTimeInterval(86_400 * 30)), "哨兵会随请求滚动，不能当截止时间")
    }

    func testRealFutureDeadlineIsStillADeadline() throws {
        // A deadline months out keeps its timestamp; only the one-day sentinel
        // is neutralised.
        let deadline = Int(Date().timeIntervalSince1970) + 86_400 * 45
        let poll = try decode(Poll.self, Self.json(
            allowvote: "1",
            expirations: String(deadline),
            remaintime: "剩余 45 天"
        ))
        XCTAssertTrue(poll.hasDeadline)
        XCTAssertFalse(poll.isClosed(at: Date()))
        // While the server still reports a countdown the poll is open by its
        // word, deadline or not; the timestamp closes it only once the countdown
        // is gone.
        XCTAssertFalse(poll.isClosed(at: Date(timeIntervalSince1970: Double(deadline) + 1)))

        let lapsed = try decode(Poll.self, Self.json(
            allowvote: "",
            expirations: String(deadline)
        ))
        XCTAssertTrue(lapsed.hasDeadline)
        XCTAssertFalse(lapsed.isClosed(at: Date()))
        XCTAssertTrue(lapsed.isClosed(at: Date(timeIntervalSince1970: Double(deadline) + 1)))
    }

    func testPastDeadlineIsClosed() throws {
        let poll = try decode(Poll.self, Self.json(
            allowvote: "",
            expirations: "1700000000"
        ))
        XCTAssertTrue(poll.isClosed(at: Self.now))
        XCTAssertFalse(poll.isClosed(at: Date(timeIntervalSince1970: 1_600_000_000)))
    }

    func testRemaintimeWinsOverTimestamp() throws {
        // When the server computed a countdown, that is the answer, even if the
        // stored timestamp looks stale.
        let poll = try decode(Poll.self, Self.json(
            allowvote: "1",
            expirations: "1000",
            remaintime: "剩余 3 天"
        ))
        XCTAssertFalse(poll.isClosed(at: Self.now))
        XCTAssertEqual(poll.remainingTime, "剩余 3 天")
    }

    func testNoExpiryFieldMeansOpen() throws {
        let poll = try decode(Poll.self, Self.fourOptions)
        XCTAssertEqual(poll.expiresAt, 0)
        XCTAssertFalse(poll.isClosed(at: Self.now.addingTimeInterval(10_000_000)))
    }

    // MARK: - Applying a vote

    func testApplyingVoteRaisesTheChosenOptionAndTheTotal() throws {
        let poll = try decode(Poll.self, Self.fourOptions)
        let voted = poll.applyingVote(["102"])

        XCTAssertEqual(voted.votersCount, 101)
        XCTAssertEqual(voted.options[1].voters, 21)
        XCTAssertEqual(voted.options[0].voters, 50)
        XCTAssertEqual(voted.options[1].percent, 21.0 / 101 * 100, accuracy: 0.001)
        XCTAssertEqual(voted.options[0].percent, 50.0 / 101 * 100, accuracy: 0.001)
        XCTAssertEqual(voted.options[1].text, "选项 B", "文字不该被票数更新动过")
    }

    func testApplyingEmptySelectionChangesNothing() throws {
        let poll = try decode(Poll.self, Self.fourOptions)
        XCTAssertEqual(poll.applyingVote([]), poll)
    }

    // MARK: - ThreadPage integration

    func testThreadPageCarriesThePoll() throws {
        let page = try decode(ThreadPage.self, """
        {
          "ppp": "40",
          "thread": {"tid": "2", "subject": "投票", "fid": "51", "closed": "1"},
          "postlist": [{"pid": "10", "tid": "2", "position": "1", "first": "1"}],
          "special_poll": \(Self.fourOptions)
        }
        """)
        XCTAssertEqual(page.thread?.fid, "51")
        XCTAssertTrue(page.thread?.isClosed ?? false)
        XCTAssertEqual(page.poll?.options.count, 4)
        XCTAssertEqual(page.posts.count, 1)
    }

    func testThreadPageWithoutPollStillDecodes() throws {
        let page = try decode(ThreadPage.self, """
        {"ppp": "40", "postlist": [{"pid": "10", "tid": "2", "position": "1"}]}
        """)
        XCTAssertNil(page.poll)
        XCTAssertEqual(page.posts.count, 1)
    }

    func testPollWithoutOptionsIsDroppedNotFatal() throws {
        let page = try decode(ThreadPage.self, """
        {
          "ppp": "40",
          "postlist": [{"pid": "10", "tid": "2", "position": "1"}],
          "special_poll": {"polloptions": [], "voterscount": "0", "allowvote": "1"}
        }
        """)
        XCTAssertNil(page.poll, "空选项的投票无法投也无法读，只能不显示")
        XCTAssertEqual(page.posts.count, 1, "投票坏了，帖子还得在")
    }

    func testMalformedPollDoesNotTakeThePostsWithIt() throws {
        let page = try decode(ThreadPage.self, """
        {
          "ppp": "40",
          "postlist": [{"pid": "10", "tid": "2", "position": "1"}],
          "special_poll": {"polloptions": {"1": {"polloptionid": {"oops": true}}}, "voterscount": "x"}
        }
        """)
        XCTAssertNil(page.poll)
        XCTAssertEqual(page.posts.count, 1)
    }

    // MARK: - Fixtures

    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    private static func json(
        allowvote: String,
        expirations: String = "0",
        remaintime: String = ""
    ) -> String {
        """
        {
          "polloptions": {
            "1": {"polloptionid": "101", "polloption": "选项 A", "votes": "50", "percent": "50.00"}
          },
          "expirations": "\(expirations)", "multiple": "0", "maxchoices": "1",
          "voterscount": "100", "visiblepoll": "0",
          "allowvote": "\(allowvote)", "remaintime": "\(remaintime)"
        }
        """
    }

    /// Ordered keys out of order on purpose: the server's dictionary order is
    /// not the ballot order.
    private static let fourOptions = """
    {
      "polloptions": {
        "2": {"polloptionid": "102", "polloption": "选项 B", "votes": "20", "percent": "20.00", "color": "00AA00"},
        "4": {"polloptionid": "104", "polloption": "选项 D", "votes": "10", "percent": "10.00"},
        "1": {"polloptionid": "101", "polloption": "选项 A", "votes": "50", "percent": "50.00", "color": "E92725"},
        "3": {"polloptionid": "103", "polloption": "选项 C", "votes": "20", "percent": "20.00"}
      },
      "expirations": "0", "multiple": "0", "maxchoices": "1",
      "voterscount": "100", "visiblepoll": "0",
      "allowvote": "1", "remaintime": ""
    }
    """
}

@MainActor
final class PollVoteStoreTests: XCTestCase {
    func testRecordIsPerAccountAndSurvivesReload() {
        let temp = TemporaryDefaults()
        let store = PollVoteStore(defaults: temp.defaults)
        store.record(tid: "9", uid: "111", options: ["101"])

        XCTAssertEqual(store.votedOptions(tid: "9", uid: "111"), ["101"])
        XCTAssertTrue(store.hasVoted(tid: "9", uid: "111"))
        XCTAssertFalse(store.hasVoted(tid: "9", uid: "222"), "换账号不能继承别人的投票")
        XCTAssertFalse(store.hasVoted(tid: "10", uid: "111"))

        let reloaded = PollVoteStore(defaults: temp.defaults)
        XCTAssertEqual(reloaded.votedOptions(tid: "9", uid: "111"), ["101"])
    }

    func testEmptyAccountIsNeverRecorded() {
        let temp = TemporaryDefaults()
        let store = PollVoteStore(defaults: temp.defaults)
        store.record(tid: "9", uid: "", options: ["101"])
        XCTAssertFalse(store.hasVoted(tid: "9", uid: ""))
    }

    func testForgetClearsOneThreadOnly() {
        let temp = TemporaryDefaults()
        let store = PollVoteStore(defaults: temp.defaults)
        store.record(tid: "9", uid: "111", options: ["101"])
        store.record(tid: "10", uid: "111", options: ["201"])

        store.forget(tid: "9", uid: "111")

        XCTAssertFalse(store.hasVoted(tid: "9", uid: "111"))
        XCTAssertTrue(store.hasVoted(tid: "10", uid: "111"))
    }
}

/// The vote body is a Discuz form: the same key, once per chosen option. A
/// dictionary would keep only the last one and silently submit a single vote.
@MainActor
final class PollVoteRequestTests: XCTestCase {
    func testVoteBodyRepeatsTheOptionKey() {
        let body = String(
            decoding: APIClient.formEncode([
                ("tid", "2127576"),
                ("formhash", "abc123"),
                ("pollsubmit", "yes"),
                ("pollanswers[]", "65925"),
                ("pollanswers[]", "65926"),
            ]),
            as: UTF8.self
        )
        XCTAssertEqual(
            body,
            "tid=2127576&formhash=abc123&pollsubmit=yes&pollanswers%5B%5D=65925&pollanswers%5B%5D=65926"
        )
    }
}

/// The three states the API cannot name outright: can vote, already voted, and
/// "cannot vote" on a page that was fetched as a guest.
@MainActor
final class PollViewModelTests: XCTestCase {
    private func summary() -> ThreadSummary {
        ThreadSummary(tid: "2", subject: "投票帖")
    }

    private func page(memberUID: String, allowvote: String, closed: String = "0") throws -> ThreadPage {
        try decode(ThreadPage.self, """
        {
          "ppp": "40",
          "member_uid": "\(memberUID)", "member_username": "\(memberUID == "0" ? "" : "someone")",
          "thread": {"tid": "2", "subject": "投票帖", "fid": "51", "closed": "\(closed)"},
          "postlist": [{"pid": "10", "tid": "2", "position": "1", "first": "1"}],
          "special_poll": {
            "polloptions": {
              "1": {"polloptionid": "101", "polloption": "A", "votes": "3", "percent": "60"},
              "2": {"polloptionid": "102", "polloption": "B", "votes": "2", "percent": "40"}
            },
            "expirations": "0", "multiple": "0", "maxchoices": "1",
            "voterscount": "5", "visiblepoll": "0",
            "allowvote": "\(allowvote)", "remaintime": ""
          }
        }
        """)
    }

    private func model(_ page: ThreadPage) -> ThreadDetailViewModel {
        ThreadDetailViewModel(summary: summary()) { _ in page }
    }

    func testSignedInOpenPollCanVote() async throws {
        let model = model(try page(memberUID: "464256", allowvote: "1"))
        await model.reload()

        XCTAssertNotNil(model.poll)
        XCTAssertFalse(model.hasVotedPoll)
        XCTAssertTrue(model.canVotePoll(isLoggedIn: true))
    }

    func testEmptyAllowVoteOnSignedInPageReadsAsAlreadyVoted() async throws {
        let model = model(try page(memberUID: "464256", allowvote: ""))
        await model.reload()

        XCTAssertTrue(model.hasVotedPoll, "已登录 + 帖子开放 + 服务器说不许投 = 已经投过")
        XCTAssertFalse(model.canVotePoll(isLoggedIn: true))
    }

    func testGuestPageWithEmptyAllowVoteIsNotAVote() async throws {
        // Guest fallback renders `allowvote` empty too; that must not become
        // "已投票" just because the account happens to be signed in.
        let model = model(try page(memberUID: "0", allowvote: ""))
        await model.reload()

        XCTAssertFalse(model.hasVotedPoll)
        XCTAssertFalse(model.canVotePoll(isLoggedIn: true))
        XCTAssertFalse(model.canVotePoll(isLoggedIn: false))
    }

    func testClosedThreadDisablesVotingAndShowsClosed() async throws {
        let model = model(try page(memberUID: "464256", allowvote: "1", closed: "1"))
        await model.reload()

        XCTAssertTrue(model.isPollClosed)
        XCTAssertFalse(model.canVotePoll(isLoggedIn: true))
    }

    func testGuestCannotVoteEvenWhenServerWouldAllow() async throws {
        let model = model(try page(memberUID: "0", allowvote: "1"))
        await model.reload()

        XCTAssertFalse(model.canVotePoll(isLoggedIn: false))
    }

    func testSingleChoiceReplacesSelection() async throws {
        let model = model(try page(memberUID: "464256", allowvote: "1"))
        await model.reload()

        model.togglePollOption("101")
        XCTAssertEqual(model.selectedPollOptionIDs, ["101"])
        model.togglePollOption("102")
        XCTAssertEqual(model.selectedPollOptionIDs, ["102"], "单选点另一项是换，不是加")
        model.togglePollOption("102")
        XCTAssertTrue(model.selectedPollOptionIDs.isEmpty, "再点一次取消")
    }

    func testMultiChoiceStopsAtMaxChoices() async throws {
        let multiple = try decode(ThreadPage.self, """
        {
          "ppp": "40", "member_uid": "464256", "member_username": "someone",
          "thread": {"tid": "2", "subject": "投票帖", "fid": "51", "closed": "0"},
          "postlist": [{"pid": "10", "tid": "2", "position": "1", "first": "1"}],
          "special_poll": {
            "polloptions": {
              "1": {"polloptionid": "101", "polloption": "A", "votes": "1", "percent": "50"},
              "2": {"polloptionid": "102", "polloption": "B", "votes": "1", "percent": "50"}
            },
            "expirations": "0", "multiple": "1", "maxchoices": "2",
            "voterscount": "2", "allowvote": "1", "remaintime": ""
          }
        }
        """)
        let model = model(multiple)
        await model.reload()

        model.togglePollOption("101")
        model.togglePollOption("102")
        XCTAssertEqual(model.selectedPollOptionIDs, ["101", "102"])
        XCTAssertNil(model.pollVoteError)

        model.selectedPollOptionIDs.insert("999") // simulate a stale tick
        model.selectedPollOptionIDs.remove("999")
        model.togglePollOption("103")
        // A third distinct option is refused; the message explains why.
        XCTAssertEqual(model.selectedPollOptionIDs.count, 2)
    }

    func testVoteRecordIsReadBackForTheSignedInAccount() async throws {
        // The view model reads the app-wide store, so the test seeds that one
        // and removes the entry again.
        PollVoteStore.shared.record(tid: "2", uid: "464256", options: ["101"])
        defer { PollVoteStore.shared.forget(tid: "2", uid: "464256") }

        let model = model(try page(memberUID: "464256", allowvote: ""))
        await model.reload()
        model.syncPollVoterRecord(uid: "464256")

        XCTAssertEqual(model.pollVotedOptionIDs, ["101"])
        XCTAssertTrue(model.hasVotedPoll)
        XCTAssertFalse(model.canVotePoll(isLoggedIn: true))
    }
}
