//
//  ContentView.swift
//  voice notes
//
//  Created by Shawn Carpenter on 1/24/26.
//
//  Note: This file is no longer used. The app entry point is NotesListView.
//  You can delete this file from the project.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        NotesListView()
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Note.self, Tag.self], inMemory: true)
}
