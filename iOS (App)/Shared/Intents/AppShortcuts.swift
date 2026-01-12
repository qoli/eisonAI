import AppIntents

struct EisonAIShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ShareToEisonAIIntent(),
            phrases: [
                "Send to \(.applicationName)",
                "Send text to \(.applicationName)",
            ],
            shortTitle: "Send to eisonAI",
            systemImageName: "square.and.arrow.down"
        )
    }

    static var shortcutTileColor: ShortcutTileColor {
        .teal
    }
}
