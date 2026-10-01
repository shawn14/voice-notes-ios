//
//  EEONAppShortcuts.swift
//  voice notes
//
//  Siri / Shortcuts / Spotlight surface for capture. "Hey Siri, record a
//  note with EEON" works with the phone locked — the intent performs in
//  the background app process.
//

import AppIntents

struct EEONAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ToggleRecordingIntent(),
            phrases: [
                "Record a note with \(.applicationName)",
                "New \(.applicationName) note",
                "Start recording in \(.applicationName)",
                "Stop recording in \(.applicationName)"
            ],
            shortTitle: "Record Note",
            systemImageName: "mic.fill"
        )
        AppShortcut(
            intent: AskEEONIntent(),
            phrases: [
                "Ask \(.applicationName)",
                "Ask \(.applicationName) a question",
                "Search my \(.applicationName) memory"
            ],
            shortTitle: "Ask EEON",
            systemImageName: "sparkle.magnifyingglass"
        )
        AppShortcut(
            intent: AddToEEONIntent(),
            phrases: [
                "Add to \(.applicationName)",
                "Save this to \(.applicationName)",
                "Send to \(.applicationName)"
            ],
            shortTitle: "Add to EEON",
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: GetRecentNotesIntent(),
            phrases: [
                "Get my recent \(.applicationName) notes",
                "What did I tell \(.applicationName) recently"
            ],
            shortTitle: "Recent Notes",
            systemImageName: "clock"
        )
    }
}
