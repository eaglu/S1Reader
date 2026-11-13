import Foundation

/// A Discuz poll attached to a thread's first post.
///
/// The mobile API sends it as `special_poll` next to `thread`/`postlist`:
///
///     "special_poll": {
///       "polloptions": {"1": {"polloptionid": "81317", "polloption": "…",
///                             "votes": "54", "percent": "17.48",
///                             "color": "E92725"}, "2": {…}},
///       "expirations": "1772937631", "multiple": "0", "maxchoices": "1",
///       "voterscount": "309", "visiblepoll": "0", "allowvote": "", "remaintime": ""
///     }
///
/// Every field is a string, `allowvote` is the server's own answer to "may this
/// account vote right now" (empty for guests, for threads that are closed, and
/// for accounts that already voted), and `polloptions` is keyed by position.
struct Poll: Hashable, Sendable {
    struct Option: Identifiable, Hashable, Sendable {
        let id: String
        let text: String
        var voters: Int
        var percent: Double
        /// Discuz's per-option colour, as `RRGGBB` without the hash.
        let color: String?

        var percentText: String { String(format: "%.1f%%", percent) }
    }

    var options: [Option]
    let multiple: Bool
    let maxChoices: Int
    /// How many accounts voted. Percentages are shares of this, not of the sum
    /// of option votes: a multi-choice poll adds up past 100%.
    var votersCount: Int
    /// `special_poll.allowvote`: the server says this account can vote now.
    let allowsVoting: Bool
    /// `visiblepoll == 1`: the author asked for results to stay hidden until a
    /// vote. Kept for the summary line, but S1's own mobile page shows the
    /// tally anyway, so the app does too.
    let hidesResults: Bool
    /// "剩余 3 天" when the poll has a real deadline; empty for open-ended ones.
    let remainingTime: String
    /// 0 when the poll never expires. Discuz otherwise sends `now + 86400` as a
    /// rolling sentinel for open-ended polls — a new value on every request — so
    /// a timestamp alone does not prove a deadline exists.
    let expiresAt: Int
    /// When this response was decoded. Only used to recognise the sentinel
    /// above, which is always exactly one day after the read.
    let decodedAt: Date
    /// Whether `expiresAt` is a deadline at all rather than the sentinel.
    let hasDeadline: Bool

    /// A poll counts as finished only when it had a real deadline that passed.
    /// An open-ended poll must never read as "closing in a day".
    func isClosed(at date: Date = Date()) -> Bool {
        guard hasDeadline, remainingTime.isEmpty else { return false }
        return expiresAt <= Int(date.timeIntervalSince1970)
    }

    var voteCount: Int { options.reduce(0) { $0 + $1.voters } }

    /// The poll as it looks right after this account's vote was accepted:
    /// every chosen option gains one vote, everyone's percentage is recomputed
    /// against the new total.
    func applyingVote(_ optionIDs: Set<String>) -> Poll {
        guard !optionIDs.isEmpty else { return self }
        var copy = self
        let total = votersCount + 1
        copy.votersCount = total
        copy.options = options.map { option in
            var updated = option
            if optionIDs.contains(option.id) { updated.voters += 1 }
            updated.percent = total > 0 ? Double(updated.voters) * 100 / Double(total) : 0
            return updated
        }
        return copy
    }
}

// MARK: - Decoding

extension Poll: Decodable {
    private struct RawOption: Decodable {
        let polloptionid: String?
        let polloption: String?
        let votes: Int?
        let percent: String?
        let color: String?

        enum CodingKeys: String, CodingKey {
            case polloptionid, polloption, votes, percent, color
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            polloptionid = container.flexStringOptional(.polloptionid)
            polloption = container.flexStringOptional(.polloption)
            votes = Int(container.flexString(.votes))
            percent = container.flexStringOptional(.percent)
            color = container.flexStringOptional(.color)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case polloptions, multiple, maxchoices, voterscount
        case visiblepoll, remaintime, expirations
        case allowvote
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // S1 sends a dictionary, but some Discuz builds send an array. Accept
        // both rather than dropping the poll over a shape difference.
        var raw: [(key: String, option: RawOption)] = []
        if let dictionary = try? container.decode([String: RawOption].self, forKey: .polloptions) {
            raw = dictionary.map { ($0.key, $0.value) }
        } else if let list = try? container.decode([RawOption].self, forKey: .polloptions) {
            raw = list.enumerated().map { (String($0.offset + 1), $0.element) }
        }

        let options = raw
            .sorted { lhs, rhs in
                if let left = Int(lhs.key), let right = Int(rhs.key) { return left < right }
                return lhs.key.localizedStandardCompare(rhs.key) == .orderedAscending
            }
            .compactMap { entry -> Option? in
                // A label is the one thing a ballot cannot invent: without it the
                // row would read "选项 1" to someone who never wrote that, so a
                // useless entry is dropped instead.
                let text = Poll.plainText(entry.option.polloption ?? "")
                guard !text.isEmpty else { return nil }
                let id = entry.option.polloptionid ?? entry.key
                guard !id.isEmpty else { return nil }
                return Option(
                    id: id,
                    text: text,
                    voters: entry.option.votes ?? 0,
                    percent: Double(entry.option.percent ?? "") ?? 0,
                    color: entry.option.color?.isEmpty == false ? entry.option.color : nil
                )
            }

        // A "poll" with no options cannot be voted on or read. Failing here
        // makes `ThreadPage` drop it and the thread still renders normally.
        guard !options.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .polloptions,
                in: container,
                debugDescription: "poll without options"
            )
        }

        let voters = container.flexInt(.voterscount)
        self.options = options.map { option in
            guard option.percent > 0 || voters <= 0 else {
                var fixed = option
                fixed.percent = Double(option.voters) * 100 / Double(voters)
                return fixed
            }
            return option
        }
        self.multiple = container.flexBool(.multiple)
        self.maxChoices = max(1, container.flexInt(.maxchoices))
        self.votersCount = voters
        self.allowsVoting = container.flexBool(.allowvote)
        self.hidesResults = container.flexInt(.visiblepoll) == 1
        self.remainingTime = Poll.trimmed(container.flexString(.remaintime))
        self.expiresAt = container.flexInt(.expirations)
        self.decodedAt = Date()
        // `expirations == decodedAt + 86400` is the "no deadline" sentinel, at
        // second granularity; a real deadline a day out would come with a
        // `remaintime` and would not track the read time on every request.
        let sentinel = abs(
            Double(expiresAt) - (decodedAt.timeIntervalSince1970 + 86_400)
        ) <= 300
        self.hasDeadline = expiresAt > 0 && !sentinel
    }
}

// MARK: - Text

extension Poll {
    /// Option labels are Discuz subjects: HTML entities plus the occasional bit
    /// of BBCode (`[url=…]`, `[b]`). The label is drawn as plain `Text`, so the
    /// markup has to go instead of showing up literally.
    static func plainText(_ raw: String) -> String {
        var text = HTMLParser.decodeEntities(raw)
        for tag in ["url", "b", "i", "u", "color", "size", "font", "backcolor", "img", "quote"] {
            text = text.replacingOccurrences(
                of: "\\[/?\(tag)(=[^\\]]*)?\\]",
                with: "",
                options: .regularExpression
            )
        }
        return trimmed(text)
    }

    static func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
