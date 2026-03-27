//
//  PostCaptureCard.swift
//  voice notes
//
//  Shows transform options after transcription completes
//

import SwiftUI

struct PostCaptureCard: View {
    let note: Note
    let onTransform: (AITransformType) -> Void
    let onViewNote: () -> Void
    let onDismiss: () -> Void

    @State private var dismissTimer: Timer?
    @State private var appeared = false

    private let quickTransforms: [AITransformType] = [
        .summary, .tweet, .meetingSummary, .executiveSummary, .prd, .ceoReport
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.85)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            VStack(spacing: 0) {
                Spacer()

                VStack(alignment: .leading, spacing: 16) {
                    // Drag indicator
                    HStack {
                        Spacer()
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.gray.opacity(0.5))
                            .frame(width: 40, height: 5)
                        Spacer()
                    }
                    .padding(.top, 12)

                    // Success indicator + title
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.green)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(note.displayTitle.isEmpty ? "New Note" : note.displayTitle)
                                .font(.headline)
                                .foregroundStyle(.white)
                                .lineLimit(1)

                            if let transcript = note.transcript, !transcript.isEmpty {
                                Text(transcript)
                                    .font(.caption)
                                    .foregroundStyle(.gray)
                                    .lineLimit(2)
                            }
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 20)

                    // Transform chips
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Transform into...")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.gray)
                            .padding(.horizontal, 20)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(quickTransforms) { type in
                                    Button {
                                        cancelTimer()
                                        onTransform(type)
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: type.icon)
                                                .font(.caption)
                                            Text(type.rawValue)
                                                .font(.caption.weight(.medium))
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 10)
                                        .background(Color.blue.opacity(0.2))
                                        .foregroundStyle(.blue)
                                        .cornerRadius(20)
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }

                    // View Note button
                    Button {
                        cancelTimer()
                        onViewNote()
                    } label: {
                        HStack {
                            Spacer()
                            Text("View Note")
                                .font(.subheadline.weight(.semibold))
                            Image(systemName: "chevron.right")
                                .font(.caption)
                            Spacer()
                        }
                        .padding(.vertical, 14)
                        .background(Color(.systemGray5).opacity(0.3))
                        .foregroundStyle(.white)
                        .cornerRadius(12)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
                .background(
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Color(.systemGray6).opacity(0.95))
                )
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
                .offset(y: appeared ? 0 : 300)
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: appeared)
            }
        }
        .onAppear {
            appeared = true
            startDismissTimer()
        }
        .onDisappear {
            cancelTimer()
        }
        .gesture(
            DragGesture()
                .onEnded { value in
                    if value.translation.height > 100 {
                        onDismiss()
                    }
                }
        )
    }

    private func startDismissTimer() {
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: false) { _ in
            DispatchQueue.main.async {
                onDismiss()
            }
        }
    }

    private func cancelTimer() {
        dismissTimer?.invalidate()
        dismissTimer = nil
    }
}
