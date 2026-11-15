import AppIntents
import Foundation

/// The decisions an intent makes, with the stores passed in.
///
/// Kept apart from the `AppIntent` types so the interesting parts — which board
/// a phrase means, which thread, what to say out loud — are unit-testable
/// without the system framework or a running Siri.
enum SiriIntentLogic {
    enum ThreadSelection: Hashable, Sendable {
        /// A thread entity the framework already resolved (Spotlight or the
        /// app's own query).
        case entity(tid: String)
        /// Words typed into Shortcuts or spoken to Siri.
        case keyword(String)
        /// No parameters at all: the thread opened most recently.
        case recent
    }

    static func resolveThread(_ selection: ThreadSelection, store: RecentThreadStore = .shared) -> RecentThread? {
        switch selection {
        case .entity(let tid):
            return store.thread(tid: tid)
        case .keyword(let keyword):
            return store.threads(matching: keyword).first
        case .recent:
            return store.threads.first
        }
    }

    /// What Siri says when the notices intent runs. Pure so the wording can be
    /// tested; `nil` means nothing has been synced yet.
    static func noticesReply(badge: NoticeBadge?, speakCount: Bool) -> String {
        guard let badge else {
            return "Opening your notices in S1. I haven't synced the unread count yet."
        }
        guard badge.loggedIn else {
            return "You're signed out in S1, so there's nothing to read yet."
        }
        guard speakCount else {
            return "Opening your notices in S1."
        }
        switch badge.unread {
        case 0:
            return "You have no unread notices in S1."
        case 1:
            return "You have 1 unread notice in S1."
        default:
            return "You have \(badge.unread) unread notices in S1."
        }
    }
}

/// The intent dialog for a piece of text.
///
/// `IntentDialog`'s string initialisers are for literals; the copy here is built
/// at runtime, so it goes through `LocalizedStringResource`'s literal init.
func intentDialog(_ text: String) -> IntentDialog {
    IntentDialog(stringLiteral: text)
}

// MARK: - Intents

// `@AppIntent(.tool)` is the Siri AI Developer Preview annotation that makes an
// intent callable by Siri as a tool. It arrives with the iOS 27.3 SDK; the flag
// keeps the app building on 27.2 and is switched on once Xcode is upgraded.
// See README, "Siri AI (Developer Preview)".

/// Opens a board's thread list.
#if SIRI_AI_PREVIEW
@AppIntent(.tool)
#endif
struct OpenForumIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Board"
    static let description = IntentDescription("Opens a Stage1st board in S1.")

    @Parameter(title: "Board", description: "The board whose thread list to open.")
    var target: ForumEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$target)")
    }

    func perform() async throws -> some IntentResult {
        PendingDeepLink.post(.forum(fid: target.fid))
        return .result()
    }
}

/// Opens a thread: the one named, the first whose title matches, or the last one
/// read.
#if SIRI_AI_PREVIEW
@AppIntent(.tool)
#endif
struct OpenThreadIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Thread"
    static let description = IntentDescription(
        "Opens a thread you have read in S1, or the one read most recently."
    )
    static var openAppWhenRun: Bool { true }

    @Parameter(
        title: "Thread",
        description: "A thread you have opened before."
    )
    var thread: ThreadEntity?

    @Parameter(
        title: "Title Contains",
        description: "Words from the thread's title, for a thread that isn't in the list."
    )
    var keyword: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$thread)")
    }

    func perform() async throws -> some IntentResult {
        let selection: SiriIntentLogic.ThreadSelection
        if let thread {
            selection = .entity(tid: thread.id)
        } else if let keyword, !keyword.trimmingCharacters(in: .whitespaces).isEmpty {
            selection = .keyword(keyword)
        } else {
            selection = .recent
        }

        guard let target = SiriIntentLogic.resolveThread(selection) else {
            return .result(dialog: intentDialog("I couldn't find that thread in S1. Open it in the app once, then ask again."))
        }
        PendingDeepLink.post(.thread(tid: target.tid, pid: nil))
        return .result(dialog: intentDialog("Opening \(target.subject) in S1."))
    }
}

/// Opens 我的 → 提醒, and says the unread count when the app has one cached.
#if SIRI_AI_PREVIEW
@AppIntent(.tool)
#endif
struct CheckNoticesIntent: AppIntent {
    static let title: LocalizedStringResource = "Check Notices"
    static let description = IntentDescription(
        "Opens your S1 notices and tells you how many are unread."
    )
    static var openAppWhenRun: Bool { true }

    @Parameter(
        title: "Say the Count",
        description: "Whether to read the unread count out loud.",
        default: true
    )
    var speakUnreadCount: Bool

    func perform() async throws -> some IntentResult {
        let badge = NoticeBadgeStore.shared.badge
        // The notice list loads in the screen itself; nothing here waits on the
        // network, so Siri answers immediately even on a slow connection.
        PendingDeepLink.post(.notices)
        return .result(dialog: intentDialog(SiriIntentLogic.noticesReply(badge: badge, speakCount: speakUnreadCount)))
    }
}
