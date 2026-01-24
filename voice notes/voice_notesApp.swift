//
//  voice_notesApp.swift
//  voice notes
//
//  Created by Shawn Carpenter on 1/24/26.
//

import SwiftUI
import SwiftData

@main
struct voice_notesApp: App {
    var body: some Scene {
        WindowGroup {
            NotesListView()
        }
        .modelContainer(for: [Note.self, Tag.self])
    }
}
