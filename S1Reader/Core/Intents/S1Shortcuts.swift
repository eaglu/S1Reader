import AppIntents

/// The phrases Siri can be asked without setting a shortcut up first.
///
/// English only: Siri AI's supported languages are English, French, Japanese,
/// Korean, Portuguese and Spanish, and Traditional Chinese is not one of them
/// yet. Parameter values may still be Chinese — "打开游戏版" type board names are
/// matched by `TextMatch`, not by the phrase.
struct S1Shortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenForumIntent(),
            phrases: [
                "Open a board in \(.applicationName)",
                "Open board \(\.$target) in \(.applicationName)"
            ],
            shortTitle: "Open board",
            systemImageName: "list.bullet.rectangle"
        )

        AppShortcut(
            intent: OpenThreadIntent(),
            phrases: [
                "Open my last thread in \(.applicationName)",
                "Open thread \(\.$thread) in \(.applicationName)"
            ],
            shortTitle: "Open thread",
            systemImageName: "text.bubble"
        )

        AppShortcut(
            intent: CheckNoticesIntent(),
            phrases: [
                "Check my notices in \(.applicationName)",
                "How many notices do I have in \(.applicationName)"
            ],
            shortTitle: "Check notices",
            systemImageName: "bell"
        )
    }

    static let shortcutTileColor: ShortcutTileColor = .blue
}
