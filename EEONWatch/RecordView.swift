//
//  RecordView.swift
//  EEONWatch
//

import SwiftUI

struct RecordView: View {
    let recorder: WatchRecorder

    var body: some View {
        VStack(spacing: 10) {
            if let startedAt = recorder.startedAt {
                Text(timerInterval: startedAt...Date.distantFuture, countsDown: false)
                    .font(.system(.title2, design: .rounded).monospacedDigit())
                    .foregroundStyle(.red)
            } else {
                Text("EEON")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            Button {
                recorder.toggle()
            } label: {
                ZStack {
                    Circle()
                        .fill(recorder.isRecording ? Color.red.opacity(0.25) : Color.red)
                        .frame(width: 84, height: 84)
                    if recorder.isRecording {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.red)
                            .frame(width: 30, height: 30)
                    } else {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 32, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(recorder.isRecording ? "Stop recording" : "Record a note")

            Text(recorder.statusLine)
                .font(.footnote)
                .foregroundStyle(recorder.statusIsProblem ? .orange : .secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 6)
    }
}
