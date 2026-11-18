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

    /// `S1_DEMO=1` fixtures for the author card's two remote sections, which
    /// otherwise cannot be seen without a real S1 session.
    static var authorThreads: [AuthorSpaceParser.ThreadItem] {
        [
            AuthorSpaceParser.ThreadItem(
                tid: "2206666",
                subject: "S1义父好人赞助楼。",
                forumName: "动漫论坛",
                replies: 326,
                views: 544504,
                lastPoster: "某位热心坛友",
                lastPost: "12 分钟前",
                dateline: ""
            ),
            AuthorSpaceParser.ThreadItem(
                tid: "2034229",
                subject: "关于新番讨论的一些想法",
                forumName: "动漫论坛",
                replies: 42,
                views: 3108,
                lastPoster: "Piano-Forest",
                lastPost: "昨天 19:42",
                dateline: ""
            ),
            AuthorSpaceParser.ThreadItem(
                tid: "1988221",
                subject: "今年最值得补的几部老番",
                forumName: "动漫论坛",
                replies: 7,
                views: 208,
                lastPoster: "活久见",
                lastPost: "3 天前",
                dateline: ""
            )
        ]
    }

    static var authorReplies: [AuthorSpaceParser.ReplyItem] {
        [
            AuthorSpaceParser.ReplyItem(
                pid: "1",
                tid: "2206666",
                threadSubject: "S1义父好人赞助楼。",
                forumName: "动漫论坛",
                snippet: "1，S1目前没有谷歌广告了，也不赚钱就不恶心人了。 2，其他广告都是短期广告，也不影响大家…",
                dateline: "",
                position: nil
            ),
            AuthorSpaceParser.ReplyItem(
                pid: "2",
                tid: "2034229",
                threadSubject: "关于新番讨论的一些想法",
                forumName: "动漫论坛",
                snippet: "这季度的制作水平确实比上一季稳，尤其是几部续作。",
                dateline: "",
                position: nil
            ),
            AuthorSpaceParser.ReplyItem(
                pid: "3",
                tid: "1988221",
                threadSubject: "今年最值得补的几部老番",
                forumName: "动漫论坛",
                snippet: "推荐先把原作补完再看动画，观感会差很多。",
                dateline: "",
                position: nil
            )
        ]
    }
}
#endif
