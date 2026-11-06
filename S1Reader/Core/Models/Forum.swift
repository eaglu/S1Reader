import Foundation

struct Member: Decodable, Equatable, Sendable {
    var uid: String = "0"
    var username: String = ""
    var avatarURL: URL?
    var formhash: String?
    var groupTitle: String = ""
    var readAccess: Int = 0
    var unreadNotices: Int = 0

    var isLoggedIn: Bool { uid != "0" && !username.isEmpty }

    enum CodingKeys: String, CodingKey {
        case uid = "member_uid"
        case username = "member_username"
        case avatar = "member_avatar"
        case formhash
        case readaccess
        case group
        case notice
    }

    private enum NoticeKeys: String, CodingKey {
        case prompt = "newprompt"
        case pm = "newpm"
    }

    private enum GroupKeys: String, CodingKey {
        case title = "grouptitle"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uid = container.flexString(.uid)
        username = HTMLParser.decodeEntities(container.flexString(.username))
        formhash = container.flexStringOptional(.formhash)
        readAccess = container.flexInt(.readaccess)
        if let avatar = container.flexStringOptional(.avatar), !avatar.isEmpty {
            avatarURL = URL(string: avatar)
        }
        if let group = try? container.nestedContainer(keyedBy: GroupKeys.self, forKey: .group) {
            groupTitle = (try? group.decode(String.self, forKey: .title)) ?? ""
        }
        if let notice = try? container.nestedContainer(keyedBy: NoticeKeys.self, forKey: .notice) {
            unreadNotices = Int((try? notice.decode(String.self, forKey: .prompt)) ?? "0") ?? 0
        }
    }

    init() {}

    init(uid: String, username: String, avatarURL: URL? = nil, formhash: String? = nil, groupTitle: String = "", readAccess: Int = 0, unreadNotices: Int = 0) {
        self.uid = uid
        self.username = username
        self.avatarURL = avatarURL
        self.formhash = formhash
        self.groupTitle = groupTitle
        self.readAccess = readAccess
        self.unreadNotices = unreadNotices
    }
}

struct Forum: Decodable, Identifiable, Hashable, Sendable {
    let fid: String
    let name: String
    let description: String
    let threads: Int
    let posts: Int
    let todayPosts: Int
    let subforums: [Forum]

    var id: String { fid }

    enum CodingKeys: String, CodingKey {
        case fid, name, description, threads, posts, todayposts, sublist
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fid = container.flexString(.fid)
        name = HTMLParser.decodeEntities(container.flexString(.name))
        description = HTMLParser.decodeEntities(container.flexString(.description))
        threads = container.flexInt(.threads)
        posts = container.flexInt(.posts)
        todayPosts = container.flexInt(.todayposts)
        subforums = (try? container.decodeIfPresent([Forum].self, forKey: .sublist)) ?? []
    }

    /// Used when a link only carries a fid and the board details come from a
    /// forum listing instead of the full index.
    init(
        fid: String,
        name: String,
        description: String = "",
        threads: Int = 0,
        posts: Int = 0,
        todayPosts: Int = 0,
        subforums: [Forum] = []
    ) {
        self.fid = fid
        self.name = name
        self.description = description
        self.threads = threads
        self.posts = posts
        self.todayPosts = todayPosts
        self.subforums = subforums
    }
}

struct ForumCategory: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let forumIDs: [String]

    enum CodingKeys: String, CodingKey {
        case fid, name, forums
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.flexString(.fid)
        name = HTMLParser.decodeEntities(container.flexString(.name))
        forumIDs = (try? container.decode([String].self, forKey: .forums)) ?? []
    }
}

struct ForumIndex: Decodable, Sendable {
    let member: Member
    let forums: [Forum]
    let categories: [ForumCategory]

    enum CodingKeys: String, CodingKey {
        case forumlist, catlist
    }

    init(from decoder: Decoder) throws {
        member = (try? Member(from: decoder)) ?? Member()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        forums = (try? container.decode([Forum].self, forKey: .forumlist)) ?? []
        categories = (try? container.decode([ForumCategory].self, forKey: .catlist)) ?? []
    }
}
