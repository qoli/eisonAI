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

//        Keep the unfinished shortcut implementation in the codebase, but
//        hide its public App Shortcut entry until the feature is complete.
//        AppShortcut(
//            intent: CallCognitiveIndexIntent(),
//            phrases: [
//                "Key points from clipboard in \(.applicationName)",
//                "Summarize clipboard with \(.applicationName)",
//            ],
//            shortTitle: "Clipboard Key Points",
//            systemImageName: "doc.on.clipboard"
//        )
    }

    static var shortcutTileColor: ShortcutTileColor {
        .teal
    }
}
