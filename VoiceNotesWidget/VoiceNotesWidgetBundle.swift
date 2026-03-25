//
//  VoiceNotesWidgetBundle.swift
//  VoiceNotesWidget
//
//  Widget extension bundle — provides Home Screen and Lock Screen widgets
//

import WidgetKit
import SwiftUI

@main
struct VoiceNotesWidgetBundle: WidgetBundle {
    var body: some Widget {
        VoiceNotesSmallWidget()
        VoiceNotesLockScreenWidget()
    }
}
