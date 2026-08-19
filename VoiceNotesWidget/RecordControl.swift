//
//  RecordControl.swift
//  VoiceNotesWidget
//
//  iOS 18 control: one button for Control Center, the Lock Screen, and the
//  Action Button. Runs ToggleRecordingIntent — start/stop background capture
//  without opening the app.
//

import WidgetKit
import SwiftUI

struct RecordControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.eeon.voicenotes.recordControl") {
            ControlWidgetButton(action: ToggleRecordingIntent()) {
                Label("Record EEON Note", systemImage: "mic.fill")
            }
        }
        .displayName("Record EEON Note")
        .description("Start or stop an EEON voice note.")
    }
}
