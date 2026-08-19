//
//  RecordingLiveActivity.swift
//  VoiceNotesWidget
//
//  The "device screen": lock screen + Dynamic Island UI for an in-flight
//  recording. Required by AudioRecordingIntent — recording stops if no
//  Live Activity is active.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct RecordingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingActivityAttributes.self) { context in
            // Lock screen banner
            HStack(spacing: 12) {
                recordingIndicator(isPaused: context.state.isPaused)
                VStack(alignment: .leading, spacing: 2) {
                    Text("EEON")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    if context.state.isPaused {
                        Text(context.state.pausedReason ?? "Paused")
                            .font(.headline)
                    } else {
                        Text(context.state.startedAt, style: .timer)
                            .font(.headline.monospacedDigit())
                    }
                }
                Spacer()
                Button(intent: StopRecordingIntent()) {
                    Label("Stop", systemImage: "stop.circle.fill")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.6))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    recordingIndicator(isPaused: context.state.isPaused)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.isPaused {
                        Text("Paused").font(.headline)
                    } else {
                        Text(context.state.startedAt, style: .timer)
                            .font(.headline.monospacedDigit())
                            .frame(maxWidth: 60)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        if let reason = context.state.pausedReason, context.state.isPaused {
                            Text(reason).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(intent: StopRecordingIntent()) {
                            Label("Stop", systemImage: "stop.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.isPaused ? "pause.fill" : "mic.fill")
                    .foregroundStyle(.red)
            } compactTrailing: {
                if context.state.isPaused {
                    Image(systemName: "phone.fill").foregroundStyle(.secondary)
                } else {
                    Text(context.state.startedAt, style: .timer)
                        .monospacedDigit()
                        .frame(maxWidth: 44)
                }
            } minimal: {
                Image(systemName: "mic.fill").foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private func recordingIndicator(isPaused: Bool) -> some View {
        Image(systemName: isPaused ? "pause.circle.fill" : "record.circle")
            .font(.title2)
            .foregroundStyle(isPaused ? .secondary : Color.red)
            .symbolEffect(.pulse, isActive: !isPaused)
    }
}
