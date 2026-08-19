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
    }
}
