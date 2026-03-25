//
//  VoiceNotesSmallWidget.swift
//  VoiceNotesWidget
//
//  Small Home Screen widget — shows last note preview + record button + usage meter
//

import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Timeline Entry

struct VoiceNotesEntry: TimelineEntry {
    let date: Date
    let lastNotePreview: String?
    let lastNoteDate: Date?
    let lastNoteIntent: String?
    let noteCount: Int
    let isPro: Bool
    let totalNotes: Int
}

// MARK: - Timeline Provider

struct VoiceNotesTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> VoiceNotesEntry {
        VoiceNotesEntry(
            date: Date(),
            lastNotePreview: "Tap to record a voice note...",
            lastNoteDate: Date(),
            lastNoteIntent: "Idea",
            noteCount: 2,
            isPro: false,
            totalNotes: 12
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (VoiceNotesEntry) -> Void) {
        completion(createEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<VoiceNotesEntry>) -> Void) {
        let entry = createEntry()
        // Refresh every 30 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func createEntry() -> VoiceNotesEntry {
        VoiceNotesEntry(
            date: Date(),
            lastNotePreview: SharedDefaults.lastNotePreview,
            lastNoteDate: SharedDefaults.lastNoteDate,
            lastNoteIntent: SharedDefaults.lastNoteIntent,
            noteCount: SharedDefaults.noteCount,
            isPro: SharedDefaults.isPro,
            totalNotes: SharedDefaults.totalNotes
        )
    }
}

// MARK: - Small Widget View

struct VoiceNotesSmallWidgetView: View {
    var entry: VoiceNotesEntry

    private var intentIcon: String {
        switch entry.lastNoteIntent {
        case "Action": return "checkmark.circle.fill"
        case "Decision": return "checkmark.seal.fill"
        case "Idea": return "lightbulb.fill"
        case "Update": return "arrow.triangle.2.circlepath"
        case "Reminder": return "bell.fill"
        default: return "waveform"
        }
    }

    private var intentColor: Color {
        switch entry.lastNoteIntent {
        case "Action": return .orange
        case "Decision": return .green
        case "Idea": return .blue
        case "Update": return .blue
        case "Reminder": return .red
        default: return .gray
        }
    }

    private var timeAgo: String {
        guard let date = entry.lastNoteDate else { return "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with app identity
            HStack {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.red)
                Text("EEON")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer()
                if !entry.isPro {
                    Text("\(SharedDefaults.freeNoteLimit - entry.noteCount) left")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.orange)
                }
            }

            Spacer()

            // Last note preview
            if let preview = entry.lastNotePreview, !preview.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: intentIcon)
                        .font(.system(size: 10))
                        .foregroundStyle(intentColor)
                    Text(preview)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(2)
                        .foregroundStyle(.primary)
                }
            } else {
                Text("No notes yet")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            if !timeAgo.isEmpty {
                Text(timeAgo)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Record button
            Link(destination: URL(string: "voicenotes://record")!) {
                HStack {
                    Spacer()
                    Image(systemName: "mic.fill")
                        .font(.system(size: 14, weight: .bold))
                    Text("Record")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                }
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.red)
                )
                .foregroundStyle(.white)
            }

            // Usage meter for free users
            if !entry.isPro {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.gray.opacity(0.3))
                            .frame(height: 3)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(
                                entry.noteCount >= SharedDefaults.freeNoteLimit
                                    ? Color.red
                                    : Color.orange
                            )
                            .frame(
                                width: geo.size.width * CGFloat(min(entry.noteCount, SharedDefaults.freeNoteLimit)) / CGFloat(SharedDefaults.freeNoteLimit),
                                height: 3
                            )
                    }
                }
                .frame(height: 3)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Widget Configuration

struct VoiceNotesSmallWidget: Widget {
    let kind: String = "VoiceNotesSmallWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: VoiceNotesTimelineProvider()) { entry in
            VoiceNotesSmallWidgetView(entry: entry)
        }
        .configurationDisplayName("Voice Notes")
        .description("Quick access to record and see your latest note.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Preview

#Preview(as: .systemSmall) {
    VoiceNotesSmallWidget()
} timeline: {
    VoiceNotesEntry(
        date: Date(),
        lastNotePreview: "Reschedule the board meeting to next Tuesday",
        lastNoteDate: Date().addingTimeInterval(-3600),
        lastNoteIntent: "Action",
        noteCount: 3,
        isPro: false,
        totalNotes: 12
    )
    VoiceNotesEntry(
        date: Date(),
        lastNotePreview: nil,
        lastNoteDate: nil,
        lastNoteIntent: nil,
        noteCount: 0,
        isPro: true,
        totalNotes: 0
    )
}
