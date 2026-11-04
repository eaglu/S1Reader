import Foundation

/// One entry of the "提醒" list (module=mynotelist).
struct Notice: Decodable, Identifiable, Sendable {
    let id: String
    let author: String
    let authorID: String
    let note: String
    let tid: String
    let pid: String
    let dateline: Date?

    enum CodingKeys: String, CodingKey {
        case id, author, authorid, note, tid, pid, dateline
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.flexString(.id)
        author = HTMLParser.decodeEntities(container.flexString(.author))
        authorID = container.flexString(.authorid)
        note = HTMLParser.decodeEntities(container.flexString(.note))
        tid = container.flexString(.tid)
        pid = container.flexString(.pid)
        dateline = Formatters.date(from: container.flexString(.dateline))
    }

    init(id: String, author: String, authorID: String = "", note: String, tid: String, pid: String = "", dateline: Date? = nil) {
        self.id = id
        self.author = author
        self.authorID = authorID
        self.note = note
        self.tid = tid
        self.pid = pid
        self.dateline = dateline
    }
}

/// One entry of the "收藏" list (module=myfavthread).
struct FavoriteThread: Decodable, Identifiable, Sendable {
    let tid: String
    let subject: String
    let author: String
    let replies: Int
    let dateline: Date?

    var id: String { tid }

    enum CodingKeys: String, CodingKey {
        case tid, subject, author, replies, dateline
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tid = container.flexString(.tid)
        subject = HTMLParser.decodeEntities(container.flexString(.subject))
        author = HTMLParser.decodeEntities(container.flexString(.author))
        replies = container.flexInt(.replies)
        dateline = Formatters.date(from: container.flexString(.dateline))
    }

    init(tid: String, subject: String, author: String, replies: Int, dateline: Date? = nil) {
        self.tid = tid
        self.subject = subject
        self.author = author
        self.replies = replies
        self.dateline = dateline
    }

    var summary: ThreadSummary {
        ThreadSummary(tid: tid, subject: subject, author: author, replies: replies)
    }
}

struct NoticeList: Decodable, Sendable {
    let list: [Notice]

    enum CodingKeys: String, CodingKey { case list }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        list = (try? container.decode([Notice].self, forKey: .list)) ?? []
    }
}

struct FavoriteList: Decodable, Sendable {
    let list: [FavoriteThread]

    enum CodingKeys: String, CodingKey { case list }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        list = (try? container.decode([FavoriteThread].self, forKey: .list)) ?? []
    }
}
