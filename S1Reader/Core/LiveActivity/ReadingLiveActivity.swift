import ActivityKit
import Foundation

/// The one place that starts, updates and ends the reading Live Activity.
///
/// The screen only says "the reader is leaving this thread at this page"; the
/// rules (setting, system authorisation, one activity at a time) live here so
/// they cannot drift between the thread view, the settings toggle and the
/// widget's own re-entry.
@MainActor
enum ReadingLiveActivity {
    /// Backs the 我的 toggle. Absent means on, so an update that never ran keeps
    /// the feature available.
    static let enabledKey = "s1.liveActivity.reading"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    /// Live Activities can be switched off for the whole device; a request then
    /// fails, and there is nothing to tell the reader about it.
    static var isAuthorized: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    /// Puts the thread on the Lock Screen / in the Dynamic Island. Starts an
    /// activity, or updates the card already showing, and drops cards left over
    /// from a different thread.
    static func present(tid: String, state: ReadingActivityAttributes.ContentState) async {
        guard state.isReady else { return }
        guard isEnabled, isAuthorized else { return }

        let content = ActivityContent(state: state, staleDate: nil)
        let activities = Activity<ReadingActivityAttributes>.activities

        for activity in activities where activity.attributes.tid != tid {
            await activity.end(nil, dismissalPolicy: .immediate)
        }

        if let current = activities.first(where: { $0.attributes.tid == tid }) {
            guard current.content.state != state else { return }
            await current.update(content)
            return
        }

        do {
            _ = try Activity.request(
                attributes: ReadingActivityAttributes(tid: tid),
                content: content,
                pushType: nil
            )
            DebugHooks.log("S1 liveActivity start tid=\(tid) page=\(state.page)/\(state.pageCount)")
        } catch {
            // A refused request (settings, device policy) is not an error worth
            // interrupting a reader who is on their way out of the app.
            DebugHooks.log("S1 liveActivity start failed: \(error.localizedDescription)")
        }
    }

    /// Fire-and-forget end for view callbacks: the card is dismissed on its own
    /// as soon as ActivityKit gets around to it.
    static func end() {
        Task { await endAll() }
    }

    static func endAll() async {
        let activities = Activity<ReadingActivityAttributes>.activities
        guard !activities.isEmpty else { return }
        for activity in activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        DebugHooks.log("S1 liveActivity end count=\(activities.count)")
    }
}
