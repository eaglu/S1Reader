import Foundation
import Observation

/// Which polls this account has already voted in.
///
/// The mobile API never says "you voted" — `special_poll.allowvote` only says
/// "you cannot vote now", which also covers a closed thread, a missing group
/// permission, and a guest. Remembering the accepted vote on device is what
/// keeps "已投票" stable across launches; the ids are also what fills the
/// option row the reader picked.
///
/// Keyed by account so switching accounts on one phone does not claim a vote
/// the new account never cast.
@MainActor
@Observable
final class PollVoteStore {
    static let shared = PollVoteStore()

    private static let key = "s1.pollVotes"

    let defaults: UserDefaults

    /// account uid → thread tid → chosen poll option ids.
    private var votes: [String: [String: [String]]]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        votes = Self.load(from: defaults)
    }

    func votedOptions(tid: String, uid: String) -> [String] {
        guard !uid.isEmpty else { return [] }
        return votes[uid]?[tid] ?? []
    }

    func hasVoted(tid: String, uid: String) -> Bool {
        !votedOptions(tid: tid, uid: uid).isEmpty
    }

    func record(tid: String, uid: String, options: [String]) {
        guard !uid.isEmpty, !options.isEmpty else { return }
        var forAccount = votes[uid] ?? [:]
        forAccount[tid] = options
        votes[uid] = forAccount
        save()
    }

    func forget(tid: String, uid: String) {
        guard var forAccount = votes[uid], forAccount.removeValue(forKey: tid) != nil else { return }
        votes[uid] = forAccount.isEmpty ? nil : forAccount
        save()
    }

    private func save() {
        defaults.set(votes, forKey: Self.key)
    }

    private static func load(from defaults: UserDefaults) -> [String: [String: [String]]] {
        defaults.dictionary(forKey: key) as? [String: [String: [String]]] ?? [:]
    }
}
