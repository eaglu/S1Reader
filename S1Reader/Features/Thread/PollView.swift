import SwiftUI

/// The poll that belongs to a thread, shown directly under its first post.
///
/// Drawn with native controls rather than parsed into the post body: the ballot
/// has to stay tappable, follow Dynamic Type, and survive a results update
/// without re-parsing any HTML. Every state the API can report has a shape here
/// — voting, voted, guest, closed — and a poll the app failed to decode simply
/// never reaches this view.
struct PollView: View {
    let poll: Poll
    /// Options this account ticked, before submitting.
    let selection: Set<String>
    /// Options this account already voted for, from the local record or the
    /// server's "you cannot vote" answer.
    let votedOptionIDs: Set<String>
    let hasVoted: Bool
    let isClosed: Bool
    let isLoggedIn: Bool
    let canVote: Bool
    let isSubmitting: Bool
    let errorMessage: String?
    var onToggle: (String) -> Void
    var onSubmit: () -> Void
    var onLogin: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The bar is decoration, but it still grows a little with the text size.
    @ScaledMetric(relativeTo: .body) private var barHeight: CGFloat = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            VStack(alignment: .leading, spacing: 12) {
                ForEach(poll.options) { option in
                    optionRow(option)
                }
            }
            if canVote {
                VStack(alignment: .leading, spacing: 6) {
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    submitRow
                }
            } else {
                resultFooter
            }
        }
        .padding(16)
        .background(
            Color(uiColor: .secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityIdentifier("pollCard")
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("投票")
                    .font(.headline)
                if poll.multiple {
                    Text("多选 · 最多 \(poll.maxChoices) 项")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if isClosed {
                    statusPill("投票已结束")
                } else if hasVoted {
                    statusPill("已投票")
                } else if !poll.allowsVoting && !isLoggedIn {
                    statusPill("登录后可投票")
                }
            }
            HStack(spacing: 10) {
                Text("共 \(poll.votersCount) 人参与")
                if !isClosed, !poll.remainingTime.isEmpty {
                    Label(poll.remainingTime, systemImage: "clock")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func statusPill(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.accentColor.opacity(0.14), in: Capsule())
            .foregroundStyle(Color.accentColor)
    }

    // MARK: - Options

    @ViewBuilder
    private func optionRow(_ option: Poll.Option) -> some View {
        let isSelected = selection.contains(option.id)
        let isMine = votedOptionIDs.contains(option.id)

        let content = HStack(alignment: .firstTextBaseline, spacing: 10) {
            marker(isSelected: isSelected, isMine: isMine)
            VStack(alignment: .leading, spacing: 6) {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 2) {
                        optionTitle(option)
                        tally(option)
                    }
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        optionTitle(option)
                        Spacer(minLength: 8)
                        tally(option)
                    }
                }
                bar(option)
            }
        }
        .contentShape(Rectangle())
        // Room for a fingertip without adding padding to every row: the lines
        // already come to roughly 44pt, and voting is what this card is for.
        .padding(.vertical, 2)

        if canVote {
            Button {
                onToggle(option.id)
            } label: {
                content
            }
            .buttonStyle(.plain)
            .accessibilityLabel(option.text)
            .accessibilityValue("\(option.voters) 票，\(option.percentText)")
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        } else {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(option.text)
                .accessibilityValue("\(option.voters) 票，\(option.percentText)")
        }
    }

    private func optionTitle(_ option: Poll.Option) -> some View {
        Text(option.text)
            .font(.body)
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.leading)
    }

    private func tally(_ option: Poll.Option) -> some View {
        Text("\(option.voters) 票 · \(option.percentText)")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            // The numbers are what the row is for; a long label wraps instead of
            // cutting "25 票 · 14.4%" down to "25 票".
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(1)
    }

    @ViewBuilder
    private func marker(isSelected: Bool, isMine: Bool) -> some View {
        if canVote {
            Image(systemName: markerName(isSelected: isSelected))
                .font(.body)
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .accessibilityHidden(true)
        } else if isMine || isSelected {
            Image(systemName: "checkmark.circle.fill")
                .font(.body)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
        } else {
            // Keeps every label on the same left edge in result-only mode.
            Color.clear
                .frame(width: 0, height: 0)
        }
    }

    private func markerName(isSelected: Bool) -> String {
        if poll.multiple {
            return isSelected ? "checkmark.square.fill" : "square"
        }
        return isSelected ? "largecircle.fill.circle" : "circle"
    }

    private func bar(_ option: Poll.Option) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(barColor(option))
                    .frame(
                        width: option.percent > 0
                            ? max(geometry.size.width * option.percent / 100, CGFloat(barHeight))
                            : 0
                    )
            }
        }
        .frame(height: barHeight)
        .accessibilityHidden(true)
    }

    /// Discuz stores a per-option colour; honour it, but fall back to the app's
    /// accent when it is missing or malformed. Mixed in a dark room, the raw
    /// value is dimmed so it does not glare against black.
    private func barColor(_ option: Poll.Option) -> Color {
        guard let hex = option.color, let color = Color(hexRGB: hex) else {
            return Color.accentColor.opacity(0.75)
        }
        return color.opacity(0.8)
    }

    // MARK: - Footer

    private var submitRow: some View {
        HStack(spacing: 12) {
            Text(selection.isEmpty ? "选择一个选项后提交" : "已选 \(selection.count) 项")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Button(action: onSubmit) {
                if isSubmitting {
                    ProgressView()
                } else {
                    Text("提交投票")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(selection.isEmpty || isSubmitting)
        }
    }

    @ViewBuilder
    private var resultFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if hasVoted {
                Label(mineLine, systemImage: "checkmark.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if isClosed {
                Text("投票已结束")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if !isLoggedIn {
                HStack(spacing: 12) {
                    Text("登录后可参与投票")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button("去登录", action: onLogin)
                        .font(.footnote.weight(.semibold))
                        .buttonStyle(.borderless)
                }
            } else if !poll.allowsVoting {
                // Signed in, open, not voted, yet the server refuses: the account
                // lacks the board's vote permission (or the page loaded as a
                // guest and the API cannot tell this account voted).
                Text("当前账号暂不可投票")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// "你投给了：A、B" — a long option list is allowed to wrap to two lines.
    private var mineLine: String {
        let titles = poll.options
            .filter { votedOptionIDs.contains($0.id) }
            .map(\.text)
        guard !titles.isEmpty else { return "你已投票" }
        return "你投给了：" + titles.joined(separator: "、")
    }
}

private extension Color {
    /// `RRGGBB` (or `#RRGGBB`) as Discuz sends it.
    init?(hexRGB: String) {
        let trimmed = hexRGB.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard trimmed.count == 6, let value = UInt32(trimmed, radix: 16) else { return nil }
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
