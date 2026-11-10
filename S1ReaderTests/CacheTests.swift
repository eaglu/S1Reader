import XCTest
@testable import S1Reader

/// `PostBodyCache` + `PostNodeMirror` exist to stop a rebuilt row from being laid
/// out at the wrong height; these tests pin the contract the row relies on.
final class CacheTests: XCTestCase {

    private func post(pid: String, message: String) throws -> Post {
        try decode(Post.self, """
        {"pid": "\(pid)", "tid": "1", "message": "\(message)"}
        """)
    }

    // MARK: - Keys

    func testCacheKeySeparatesPostsAndScales() {
        XCTAssertNotEqual(
            PostBodyCache.cacheKey(pid: "1", scale: 1),
            PostBodyCache.cacheKey(pid: "2", scale: 1)
        )
        XCTAssertNotEqual(
            PostBodyCache.cacheKey(pid: "1", scale: 1),
            PostBodyCache.cacheKey(pid: "1", scale: 1.5)
        )
        XCTAssertEqual(
            PostBodyCache.cacheKey(pid: "1", scale: 1.2),
            PostBodyCache.cacheKey(pid: "1", scale: 1.2)
        )
    }

    // MARK: - PostBodyCache

    func testSecondRequestIsServedFromTheCache() async throws {
        let cache = PostBodyCache()
        let first = await cache.nodes(pid: "1", html: "第一次", scale: 1)
        // Different HTML, same pid and scale: a parse would return different text,
        // so getting the first body back proves the cache was hit.
        let second = await cache.nodes(pid: "1", html: "第二次", scale: 1)
        XCTAssertEqual(first, second)
        XCTAssertEqual(second.compactMap(\.text).joined(), "第一次")
    }

    func testDifferentScaleIsParsedSeparately() async throws {
        let cache = PostBodyCache()
        _ = await cache.nodes(pid: "1", html: "<b>字</b>", scale: 1)
        let base = await cache.nodes(pid: "1", html: "<b>字</b>", scale: 1)
        let scaled = await cache.nodes(pid: "1", html: "<b>字</b>", scale: 2)
        XCTAssertNotEqual(scaled, base, "a different text scale must not reuse the other scale's body")
        XCTAssertEqual(scaled.compactMap(\.text).joined(), base.compactMap(\.text).joined())
    }

    func testConcurrentRequestsShareOneParse() async throws {
        let cache = PostBodyCache()
        let bodies = await withTaskGroup(of: [PostNode].self) { group in
            for index in 0..<8 {
                group.addTask {
                    await cache.nodes(pid: "9", html: "并发\(index)", scale: 1)
                }
            }
            var results: [[PostNode]] = []
            for await body in group { results.append(body) }
            return results
        }
        XCTAssertEqual(bodies.count, 8)
        XCTAssertEqual(Set(bodies.map { $0.map(\.text) }), Set([bodies[0].map(\.text)]))
    }

    func testMirrorIsFilledSoTheNextRowCanDrawSynchronously() async throws {
        let cache = PostBodyCache()
        await MainActor.run { PostNodeMirror.shared.removeAll() }
        let nodes = await cache.nodes(pid: "77", html: "镜像", scale: 1)

        let mirrored = await MainActor.run { PostNodeMirror.shared.nodes(pid: "77", scale: 1) }
        XCTAssertEqual(mirrored, nodes)
    }

    func testRemoveAllClearsBothStores() async throws {
        let cache = PostBodyCache()
        _ = await cache.nodes(pid: "5", html: "内容", scale: 1)

        await cache.removeAll()
        // removeAll hops to the main actor asynchronously.
        for _ in 0..<50 {
            let mirrored = await MainActor.run { PostNodeMirror.shared.nodes(pid: "5", scale: 1) }
            if mirrored == nil { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let mirrored = await MainActor.run { PostNodeMirror.shared.nodes(pid: "5", scale: 1) }
        XCTAssertNil(mirrored)

        let again = await cache.nodes(pid: "5", html: "新内容", scale: 1)
        XCTAssertEqual(again.compactMap(\.text).joined(), "新内容", "the actor cache was cleared too")
    }

    func testWarmPrefillsTheCache() async throws {
        let cache = PostBodyCache()
        let posts = [try post(pid: "1", message: "第一帖"), try post(pid: "2", message: "第二帖")]
        await cache.warm(posts: posts, scale: 1)

        let warmed = await cache.nodes(pid: "2", html: "不该被解析", scale: 1)
        XCTAssertEqual(warmed.compactMap(\.text).joined(), "第二帖")
    }

    // MARK: - PostNodeMirror

    @MainActor
    func testMirrorEvictsOldestBodies() {
        let mirror = PostNodeMirror()
        let body = HTMLParser.parse("内容", scale: 1)
        for index in 0..<405 {
            mirror.store(body, pid: "\(index)", scale: 1)
        }
        XCTAssertNil(mirror.nodes(pid: "0", scale: 1), "the oldest entries are evicted")
        XCTAssertNotNil(mirror.nodes(pid: "404", scale: 1))
        XCTAssertNotNil(mirror.nodes(pid: "5", scale: 1), "eviction keeps a bounded window")
        XCTAssertNil(mirror.nodes(pid: "4", scale: 1))
    }

    @MainActor
    func testMirrorStoringTheSamePostTwiceDoesNotGrow() {
        let mirror = PostNodeMirror()
        let body = HTMLParser.parse("内容", scale: 1)
        mirror.store(body, pid: "1", scale: 1)
        mirror.store(HTMLParser.parse("改过", scale: 1), pid: "1", scale: 1)
        XCTAssertEqual(mirror.nodes(pid: "1", scale: 1)?.compactMap(\.text).joined(), "改过")
        XCTAssertNil(mirror.nodes(pid: "1", scale: 2))
    }
}
