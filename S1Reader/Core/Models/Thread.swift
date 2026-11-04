import Foundation

struct ThreadSummary: Decodable, Identifiable, Hashable, Sendable {
    let tid: String
    let subject: String
    let author: String
    let authorID: String
    let replies: Int
    let views: Int
    let lastPost: String
    let lastPoster: String
    let isPinned: Bool
    let isDigest: Bool
    let hasAttachment: Bool
    let previewImageURL: URL?

    var id: String { tid }

    init(
        tid: String,
        subject: String,
        author: String = "",
        authorID: String = "",
        replies: Int = 0,
        views: Int = 0,
        lastPost: String = "",
        lastPoster: String = "",
        isPinned: Bool = false,
        isDigest: Bool = false,
        hasAttachment: Bool = false,
        previewImageURL: URL? = nil
    ) {
        self.tid = tid
        self.subject = subject
        self.author = author
        self.authorID = authorID
        self.replies = replies
        self.views = views
        self.lastPost = lastPost
        self.lastPoster = lastPoster
        self.isPinned = isPinned
        self.isDigest = isDigest
        self.hasAttachment = hasAttachment
        self.previewImageURL = previewImageURL
    }

    enum CodingKeys: String, CodingKey {
        case tid, subject, author, authorid, replies, views
        case lastpost, lastposter, displayorder, digest, attachment
        case previews = "attachmentImagePreviewList"
    }

    private enum PreviewKeys: String, CodingKey {
        case attachment
        case remote
        case filename
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tid = container.flexString(.tid)
        subject = HTMLParser.decodeEntities(container.flexString(.subject))
        author = HTMLParser.decodeEntities(container.flexString(.author))
        authorID = container.flexString(.authorid)
        replies = container.flexInt(.replies)
        views = container.flexInt(.views)
        lastPost = container.flexString(.lastpost)
        lastPoster = HTMLParser.decodeEntities(container.flexString(.lastposter))
        isPinned = container.flexInt(.displayorder) > 0
        isDigest = container.flexBool(.digest)
        hasAttachment = container.flexInt(.attachment) > 0

        var previewURL: URL?
        if let previews = try? container.decodeIfPresent([Preview].self, forKey: .previews),
           let first = previews.first {
            previewURL = first.url
        }
        previewImageURL = previewURL
    }

    private struct Preview: Decodable {
        let url: URL?

        enum CodingKeys: String, CodingKey {
            case attachment, remote
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let path = container.flexString(.attachment)
            guard !path.isEmpty else {
                url = nil
                return
            }
            let remote = container.flexInt(.remote)
            if remote == 1 {
                url = URL(string: path)
            } else {
                url = URL(string: "https://stage1st.com/2b/data/attachment/forum/\(path)")
            }
        }
    }
}

struct ThreadInfo: Decodable, Sendable {
    let tid: String
    let subject: String
    let replies: Int
    let views: Int
    let author: String
    let dateline: String
    let isClosed: Bool

    enum CodingKeys: String, CodingKey {
        case tid, subject, replies, views, author, dateline, closed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tid = container.flexString(.tid)
        subject = HTMLParser.decodeEntities(container.flexString(.subject))
        replies = container.flexInt(.replies)
        views = container.flexInt(.views)
        author = HTMLParser.decodeEntities(container.flexString(.author))
        dateline = container.flexString(.dateline)
        isClosed = container.flexBool(.closed)
    }
}

struct ThreadListPage: Decodable, Sendable {
    let member: Member
    let forumName: String
    let description: String
    let threads: [ThreadSummary]
    let page: Int
    let perPage: Int
    let totalThreads: Int

    enum CodingKeys: String, CodingKey {
        case forum, forum_threadlist, page, tpp
    }

    private enum ForumKeys: String, CodingKey {
        case name, description, threads
    }

    init(from decoder: Decoder) throws {
        member = (try? Member(from: decoder)) ?? Member()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        threads = (try? container.decode([ThreadSummary].self, forKey: .forum_threadlist)) ?? []
        page = max(1, container.flexInt(.page))
        perPage = max(1, container.flexInt(.tpp))

        var name = ""
        var desc = ""
        var total = 0
        if let forum = try? container.nestedContainer(keyedBy: ForumKeys.self, forKey: .forum) {
            name = forum.flexString(.name)
            desc = forum.flexString(.description)
            total = forum.flexInt(.threads)
        }
        forumName = name
        description = desc
        totalThreads = total
    }
}

struct Post: Decodable, Identifiable, Hashable, Sendable {
    let pid: String
    let tid: String
    let author: String
    let authorID: String
    let dateline: String
    let message: String
    let position: Int
    let isFirst: Bool
    let isAdmin: Bool

    var id: String { pid }

    enum CodingKeys: String, CodingKey {
        case pid, tid, author, authorid, dateline, message
        case position, number, first, adminid
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pid = container.flexString(.pid)
        tid = container.flexString(.tid)
        author = HTMLParser.decodeEntities(container.flexString(.author))
        authorID = container.flexString(.authorid)
        dateline = container.flexString(.dateline)
        message = container.flexString(.message)
        let rawPosition = container.flexString(.position)
        position = Int(rawPosition) ?? container.flexInt(.number)
        isFirst = container.flexBool(.first)
        isAdmin = container.flexInt(.adminid) > 0
    }
}

struct ThreadPage: Decodable, Sendable {
    let member: Member
    let thread: ThreadInfo?
    let posts: [Post]
    let perPage: Int

    enum CodingKeys: String, CodingKey {
        case thread, postlist, ppp
    }

    init(from decoder: Decoder) throws {
        member = (try? Member(from: decoder)) ?? Member()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        thread = try? container.decodeIfPresent(ThreadInfo.self, forKey: .thread)
        posts = (try? container.decode([Post].self, forKey: .postlist)) ?? []
        perPage = max(1, container.flexInt(.ppp))
    }
}
