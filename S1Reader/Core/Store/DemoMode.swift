#if DEBUG
import Foundation

/// Debug-only fixtures so the signed-in screens can be inspected without
/// a real account: `S1_DEMO=1` when launching from the command line.
enum DemoMode {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["S1_DEMO"] == "1"
    }

    static func member() -> Member {
        Member(
            uid: "123456",
            username: "S1er",
            groupTitle: "管理员",
            readAccess: 100,
            unreadNotices: 3
        )
    }

    static var notices: [Notice] {
        [
            Notice(
                id: "1",
                author: "活久见",
                note: "有人回复了你的主题《关于新番讨论的一些想法》",
                tid: "2206666",
                pid: "1",
                dateline: Date().addingTimeInterval(-600)
            ),
            Notice(
                id: "2",
                author: "Piano-Forest",
                note: "提到了你：@S1er 这个季度还有推荐的片子吗？",
                tid: "2034229",
                pid: "2",
                dateline: Date().addingTimeInterval(-3600 * 5)
            ),
            Notice(
                id: "3",
                author: "harry",
                note: "赞了你的帖子",
                tid: "2206666",
                pid: "3",
                dateline: Date().addingTimeInterval(-86_400 * 2)
            )
        ]
    }

    static var favorites: [FavoriteThread] {
        [
            FavoriteThread(
                tid: "2206666",
                subject: "S1义父好人赞助楼。",
                author: "活久见",
                replies: 326,
                dateline: Date().addingTimeInterval(-3600 * 30)
            ),
            FavoriteThread(
                tid: "2034229",
                subject: "2022.10『想要成为影之实力者』 剧场动画残响篇制作决定",
                author: "Piano-Forest",
                replies: 7109,
                dateline: Date().addingTimeInterval(-3600 * 2)
            )
        ]
    }
}
#endif
