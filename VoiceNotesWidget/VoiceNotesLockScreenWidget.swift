//
//  VoiceNotesLockScreenWidget.swift
//  VoiceNotesWidget
//
//  Lock Screen widget (accessoryCircular) — mic icon that deep-links to recording
//

import WidgetKit
import SwiftUI

// MARK: - Lock Screen Widget View

struct VoiceNotesLockScreenView: View {
    var entry: VoiceNotesEntry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            Image(systemName: "mic.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.primary)
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: "voicenotes://record"))
    }
}

// MARK: - Lock Screen Inline View (accessoryInline)

struct VoiceNotesInlineView: View {
    var entry: VoiceNotesEntry

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "mic.fill")
            if let preview = entry.lastNotePreview {
                Text(preview)
                    .lineLimit(1)
            } else {
                Text("Record a note")
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: "voicenotes://record"))
    }
}

// MARK: - Lock Screen Rectangular View (accessoryRectangular)

struct VoiceNotesRectangularView: View {
    var entry: VoiceNotesEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 12, weight: .bold))
                Text("EEON")
                    .font(.system(size: 11, weight: .bold))
            }

            if let preview = entry.lastNotePreview {
                Text(preview)
                    .font(.system(size: 12))
                    .lineLimit(2)
                    .foregroundStyle(.secondary)
            } else {
                Text("Tap to record")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            if !entry.isPro && entry.noteCount > 0 {
                Text("\(SharedDefaults.freeNoteLimit - entry.noteCount)/\(SharedDefaults.freeNoteLimit) free notes left")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: "voicenotes://record"))
    }
}

// MARK: - Widget Configuration

struct VoiceNotesLockScreenWidget: Widget {
    let kind: String = "VoiceNotesLockScreenWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: VoiceNotesTimelineProvider()) { entry in
            VoiceNotesLockScreenView(entry: entry)
        }
        .configurationDisplayName("Quick Record")
        .description("One-tap voice recording from your Lock Screen.")
        .supportedFamilies([.accessoryCircular, .accessoryInline, .accessoryRectangular])
    }
}

// MARK: - Preview

#Preview(as: .accessoryCircular) {
    VoiceNotesLockScreenWidget()
} timeline: {
    VoiceNotesEntry(
        date: Date(),
        lastNotePreview: "Board meeting recap",
        lastNoteDate: Date(),
        lastNoteIntent: "Update",
        noteCount: 2,
        isPro: false,
        totalNotes: 8
    )
}
