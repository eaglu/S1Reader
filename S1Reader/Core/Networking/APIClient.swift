import Foundation

enum APIError: LocalizedError {
    case badURL
    case http(Int)
    case transport(Error)
    case server(String)
    case decoding(Error)
    case notLoggedIn

    var errorDescription: String? {
        switch self {
        case .badURL:
            return "请求地址无效"
        case .http(let code):
            return "服务器返回 HTTP \(code)"
        case .transport(let error):
            return "网络错误：\(error.localizedDescription)"
        case .server(let message):
            return message
        case .decoding:
            return "数据解析失败，接口可能已变更"
        case .notLoggedIn:
            return "请先登录"
        }
    }
}

struct APIMessage: Decodable, Sendable {
    let value: String?
    let text: String?

    enum CodingKeys: String, CodingKey {
        case value = "messageval"
        case text = "messagestr"
    }
}

struct APIEnvelope<T: Decodable>: Decodable {
    let variables: T?
    let message: APIMessage?

    enum CodingKeys: String, CodingKey {
        case variables = "Variables"
        case message = "Message"
    }
}

/// Last non-2xx response, kept so the UI can offer copyable diagnostics.
struct APIFailure: Sendable {
    let status: Int
    let module: String
    let bodyPrefix: String
    let wasGuest: Bool
}

/// Thin client for the Discuz! mobile API exposed by stage1st.com.
actor APIClient {
    static let shared = APIClient()

    static let baseURL = URL(string: "https://stage1st.com/2b/")!
    private let endpoint = URL(string: "https://stage1st.com/2b/api/mobile/index.php")!

    private let session: URLSession
    var formhash: String?
    var member: Member?
    private(set) var lastFailure: APIFailure?

    /// Whether the cookie jar still holds a Discuz session.
    nonisolated static var hasStoredSession: Bool {
        (HTTPCookieStorage.shared.cookies ?? []).contains {
            $0.name.hasSuffix("_auth") && !$0.value.isEmpty
        }
    }

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = HTTPCookieStorage.shared
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpShouldSetCookies = true
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 20
        configuration.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148",
            "Accept-Language": "zh-CN,zh-Hans;q=0.9",
            "Referer": "https://stage1st.com/2b/"
        ]
        session = URLSession(configuration: configuration)
    }

    var cachedMember: Member? { member }
    var cachedFormhash: String? { formhash }

    /// `guest: true` sends the request without cookies, for retrying a thread that
    /// only fails while a session is attached.
    func fetch<T: Decodable>(
        _ module: String,
        _ params: [String: String] = [:],
        guest: Bool = false
    ) async throws -> T {
        let data = try await rawFetch(module, params, guest: guest)

        do {
            let envelope = try JSONDecoder().decode(APIEnvelope<T>.self, from: data)
            if let variables = envelope.variables {
                if let index = variables as? ForumIndex {
                    member = index.member
                    formhash = index.member.formhash
                }
                return variables
            }
            if let message = envelope.message {
                let value = message.value ?? ""
                if value.contains("to_login") || value.contains("login_before") {
                    resetSession()
                    throw APIError.notLoggedIn
                }
                throw APIError.server(message.text ?? value)
            }
            throw APIError.server("接口没有返回数据")
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.decoding(error)
        }
    }

    /// Retries transient failures: S1 answers 503 (a bare Discuz "System Error"
    /// page) both when it is overloaded and when a request is rate limited.
    private func rawFetch(
        _ module: String,
        _ params: [String: String],
        guest: Bool = false
    ) async throws -> Data {
        var attempt = 0
        while true {
            do {
                return try await performFetch(module, params, guest: guest)
            } catch let error as APIError {
                attempt += 1
                guard attempt < 3, Self.isRetryable(error) else { throw error }
                try? await Task.sleep(for: .milliseconds(attempt == 1 ? 400 : 1200))
            }
        }
    }

    /// First part of an error page, with the markup flattened for display.
    private static func snippet(of data: Data) -> String {
        let text = String(decoding: data.prefix(2000), as: UTF8.self)
        let flattened = text
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(flattened.prefix(200))
    }

    /// Diagnostics for the "copy" button in the error view.
    func diagnostics() -> String {
        let failure = lastFailure
        let loggedIn = member != nil ? "已登录（\(member?.username ?? "")）" : "未登录"
        return [
            "S1Reader 诊断",
            "module: \(failure?.module ?? "-")",
            "status: \(failure.map { String($0.status) } ?? "200/未知")",
            "guest: \(failure?.wasGuest == true ? "是" : "否")",
            "session: \(Self.hasStoredSession ? "有 auth cookie" : "无 auth cookie")",
            "account: \(loggedIn)",
            "body: \(failure?.bodyPrefix ?? "-")"
        ].joined(separator: "\n")
    }

    private static func isRetryable(_ error: APIError) -> Bool {
        switch error {
        case .http(let code):
            return code == 429 || code == 502 || code == 503 || code == 504
        case .transport:
            return true
        default:
            return false
        }
    }

    private func performFetch(
        _ module: String,
        _ params: [String: String],
        guest: Bool = false
    ) async throws -> Data {
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw APIError.badURL
        }
        var items = [
            URLQueryItem(name: "version", value: "4"),
            URLQueryItem(name: "module", value: module),
            URLQueryItem(name: "mobile", value: "2")
        ]
        items.append(contentsOf: params.sorted { $0.key < $1.key }.map {
            URLQueryItem(name: $0.key, value: $0.value)
        })
        components.queryItems = items

        guard let url = components.url else { throw APIError.badURL }
        var request = URLRequest(url: url)
        request.setValue("https://stage1st.com/2b/", forHTTPHeaderField: "Referer")
        request.httpShouldHandleCookies = !guest

        #if DEBUG
        // S1_FORCE_503=1 makes the first (cookie-carrying) attempt fail so the guest
        // fallback can be exercised without a real account; =2 also fails the retry
        // so the error screen (and its diagnostics button) can be checked.
        if let mode = ProcessInfo.processInfo.environment["S1_FORCE_503"],
           module == "viewthread",
           mode == "2" || (!guest && mode == "1") {
            lastFailure = APIFailure(
                status: 503,
                module: module,
                bodyPrefix: "stage1st.com - System Error（模拟）",
                wasGuest: guest
            )
            throw APIError.http(503)
        }
        #endif

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.transport(error)
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            lastFailure = APIFailure(
                status: http.statusCode,
                module: module,
                bodyPrefix: Self.snippet(of: data),
                wasGuest: guest
            )
            throw Self.httpError(http.statusCode)
        }
        return data
    }

    // MARK: - Authentication

    struct LoginInput: Sendable {
        var username: String
        var password: String
        var questionID: Int = 0
        var answer: String = ""
    }

    /// Keeps a single cookie per name: leftover duplicates from earlier sessions make
    /// Discuz read a stale `auth` value.
    private func pruneDuplicateCookies() {
        let store = HTTPCookieStorage.shared
        let cookies = store.cookies ?? []
        let s1 = cookies.filter { $0.domain.hasSuffix("stage1st.com") }
        let duplicates = Dictionary(grouping: s1, by: { "\($0.name)|\($0.path)" })
            .values
            .filter { $0.count > 1 }
        for group in duplicates {
            let sorted = group.sorted { $0.expiresDate ?? .distantPast < $1.expiresDate ?? .distantPast }
            for cookie in sorted.dropLast() {
                store.deleteCookie(cookie)
            }
        }
    }

    func login(_ input: LoginInput) async throws -> Member {
        var fields: [String: String] = [
            "action": "login",
            "username": input.username,
            "password": input.password,
            "cookietime": "2592000",
            "loginsubmit": "true"
        ]
        if let formhash, !formhash.isEmpty {
            fields["formhash"] = formhash
        }
        if input.questionID > 0 {
            fields["questionid"] = String(input.questionID)
            fields["answer"] = input.answer
        }

        let data = try await rawPost("login", fields)
        let envelope = try decodeEnvelope(Member.self, from: data)

        if let loggedIn = envelope.variables, loggedIn.isLoggedIn {
            pruneDuplicateCookies()
            member = loggedIn
            formhash = loggedIn.formhash ?? formhash
            return loggedIn
        }
        if let message = envelope.message {
            throw APIError.server(message.text ?? message.value ?? "登录失败")
        }
        throw APIError.server("登录失败，请检查账号密码")
    }

    struct ReplyResult: Decodable, Sendable {
        let pid: String?
        enum CodingKeys: String, CodingKey { case pid }
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            pid = container.flexStringOptional(.pid)
        }
    }

    /// Posts a reply and returns the new post id when the server reports success.
    @discardableResult
    func reply(tid: String, message: String) async throws -> String? {
        guard let formhash, !formhash.isEmpty else { throw APIError.notLoggedIn }
        let data = try await rawPost("sendreply", [
            "tid": tid,
            "message": message,
            "formhash": formhash,
            "usesig": "1"
        ])
        let envelope = try decodeEnvelope(ReplyResult.self, from: data)
        if let message = envelope.message {
            let value = message.value ?? ""
            if value.contains("succeed") || value.contains("success") {
                return envelope.variables?.pid
            }
            throw APIError.server(message.text ?? value)
        }
        return envelope.variables?.pid
    }

    /// Adds the thread to (or removes it from) the user's favorites.
    func setFavorite(tid: String, favorite: Bool) async throws {
        guard let formhash, !formhash.isEmpty else { throw APIError.notLoggedIn }
        let data = try await rawPost("favthread", [
            "action": favorite ? "add" : "delete",
            "tid": tid,
            "formhash": formhash
        ])
        let envelope = try decodeEnvelope(EmptyVariables.self, from: data)
        if let message = envelope.message {
            let value = message.value ?? ""
            let text = message.text ?? value
            let isSuccess = value.contains("succeed")
                || value.contains("do_success")
                || value.contains("favorite")
                || text.contains("已收藏")
                || text.contains("收藏成功")
            if isSuccess { return }
            throw APIError.server(text)
        }
    }

    struct EmptyVariables: Decodable, Sendable {}

    func notices(page: Int = 1) async throws -> [Notice] {
        let result: NoticeList = try await fetch("mynotelist", ["page": String(page)])
        return result.list
    }

    func favorites(page: Int = 1) async throws -> [FavoriteThread] {
        let result: FavoriteList = try await fetch("myfavthread", ["page": String(page)])
        return result.list
    }

    func logout() async {
        if let formhash {
            _ = try? await rawPost("login", ["action": "logout", "formhash": formhash])
        }
        resetSession()
    }

    private func decodeEnvelope<T: Decodable>(_ type: T.Type, from data: Data) throws -> APIEnvelope<T> {
        do {
            return try JSONDecoder().decode(APIEnvelope<T>.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    private func rawPost(_ module: String, _ fields: [String: String]) async throws -> Data {
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw APIError.badURL
        }
        components.queryItems = [
            URLQueryItem(name: "version", value: "4"),
            URLQueryItem(name: "module", value: module),
            URLQueryItem(name: "mobile", value: "2")
        ]
        guard let url = components.url else { throw APIError.badURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("https://stage1st.com/2b/", forHTTPHeaderField: "Referer")
        request.httpBody = Self.formEncode(fields)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.transport(error)
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw Self.httpError(http.statusCode)
        }
        return data
    }

    private static func httpError(_ code: Int) -> APIError {
        switch code {
        case 503:
            // Discuz answers 503 for an overloaded server *and* for threads the
            // current session is not allowed to read, so say both.
            return .server("S1 返回 503：服务器繁忙，或本帖需要登录／更高的阅读权限。请稍后重试。")
        case 429:
            return .server("请求太频繁，请稍后再试")
        default:
            return .http(code)
        }
    }

    private static func formEncode(_ fields: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let body = fields
            .map { key, value in
                let encodedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
                let encodedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(encodedKey)=\(encodedValue)"
            }
            .joined(separator: "&")
        return Data(body.utf8)
    }

    /// Removes the cached formhash / member, used after logging out.
    func resetSession() {
        formhash = nil
        member = nil
        if let cookies = HTTPCookieStorage.shared.cookies(for: Self.baseURL) {
            cookies.forEach(HTTPCookieStorage.shared.deleteCookie)
        }
    }
}
