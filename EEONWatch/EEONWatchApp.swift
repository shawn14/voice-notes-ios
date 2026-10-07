//
//  EEONWatchApp.swift
//  EEONWatch
//
//  EEON on the wrist: one button that records a note. The recording is handed
//  to the iPhone (WatchConnectivity file transfer), where the normal pipeline
//  transcribes it and turns it into a note. Nothing is transcribed or stored
//  long-term on the watch.
//

import SwiftUI

@main
struct EEONWatchApp: App {
    @State private var recorder = WatchRecorder()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RecordView(recorder: recorder)
                .onAppear { recorder.activate() }
        }
        // Each time the app comes forward, re-queue anything that failed to send.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { recorder.activate() }
        }
    }
}
