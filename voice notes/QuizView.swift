//
//  QuizView.swift
//  voice notes
//
//  Flashcard practice over a note's questions (2026-08-20).
//
//  WHY A CARD AND NOT A LIST
//  The School Notes format already prints review questions under the note —
//  and reading a question with its answer visible two lines below is
//  recognition, not recall. You feel like you know it because you just read
//  it. One question at a time, answer hidden until you commit, is the whole
//  mechanism; everything else here is in service of that.
//
//  Missed questions cycle back in a second pass rather than being scored and
//  forgotten, because the point is to end knowing them, not to get a grade.
//

import SwiftUI
import SwiftData

struct QuizView: View {
    let note: Note
    let questions: [QuizQuestion]

    @Environment(\.dismiss) private var dismiss

    @State private var queue: [QuizQuestion] = []
    @State private var index = 0
    @State private var isRevealed = false
    @State private var missed: [QuizQuestion] = []
    @State private var correctCount = 0
    @State private var isSecondPass = false
    @State private var isFinished = false

    private var current: QuizQuestion? {
        guard index < queue.count else { return nil }
        return queue[index]
    }

    private var progressText: String {
        guard !queue.isEmpty else { return "" }
        return "\(min(index + 1, queue.count)) of \(queue.count)"
    }

    var body: some View {
        NavigationStack {
            Group {
                if isFinished {
                    resultsScreen
                } else if let question = current {
                    cardScreen(question)
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.eeonBackground)
            .navigationTitle(isSecondPass ? "Second pass" : "Quiz")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    if !isFinished {
                        Text(progressText)
                            .font(EEONType.meta)
                            .foregroundStyle(.eeonTextSecondary)
                    }
                }
            }
        }
        .onAppear {
            if queue.isEmpty { queue = questions.shuffled() }
        }
    }

    // MARK: - Card

    private func cardScreen(_ question: QuizQuestion) -> some View {
        VStack(spacing: EEONLayout.loose) {
            progressBar

            Spacer(minLength: 0)

            VStack(spacing: EEONLayout.standard) {
                Text(question.question)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.eeonTextPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if isRevealed {
                    Divider()
                        .padding(.vertical, EEONLayout.tight)

                    Text(question.answer)
                        .font(EEONType.body)
                        .foregroundStyle(.eeonTextSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .padding(EEONLayout.loose)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: EEONLayout.cardRadius)
                    .fill(Color.eeonCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: EEONLayout.cardRadius)
                    .strokeBorder(Color.eeonTextTertiary.opacity(0.18), lineWidth: 1)
            )
            .onTapGesture {
                if !isRevealed {
                    withAnimation(.easeOut(duration: 0.2)) { isRevealed = true }
                }
            }

            Spacer(minLength: 0)

            if isRevealed {
                gradeButtons
            } else {
                revealButton
            }
        }
        .padding(EEONLayout.screenMargin)
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.eeonTextTertiary.opacity(0.18))
                Capsule()
                    .fill(Color.eeonAccent)
                    .frame(width: geo.size.width * fraction)
            }
        }
        .frame(height: 4)
    }

    private var fraction: CGFloat {
        guard !queue.isEmpty else { return 0 }
        return CGFloat(index) / CGFloat(queue.count)
    }

    private var revealButton: some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) { isRevealed = true }
        } label: {
            Text("Show answer")
                .font(EEONType.control)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
                .background(
                    RoundedRectangle(cornerRadius: EEONLayout.chipRadius)
                        .fill(Color.eeonAccent)
                )
        }
        .buttonStyle(.plain)
    }

    /// Self-grading. There is no text entry on purpose: typing an answer on a
    /// phone is friction that stops people practising, and the recall already
    /// happened in the beat before the answer appeared.
    private var gradeButtons: some View {
        HStack(spacing: EEONLayout.snug) {
            Button {
                advance(gotIt: false)
            } label: {
                Label("Missed it", systemImage: "arrow.counterclockwise")
                    .font(EEONType.control)
                    .foregroundStyle(.eeonTextPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
                    .background(
                        RoundedRectangle(cornerRadius: EEONLayout.chipRadius)
                            .fill(Color.eeonCard)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: EEONLayout.chipRadius)
                            .strokeBorder(Color.eeonTextTertiary.opacity(0.3), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            Button {
                advance(gotIt: true)
            } label: {
                Label("Got it", systemImage: "checkmark")
                    .font(EEONType.control)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
                    .background(
                        RoundedRectangle(cornerRadius: EEONLayout.chipRadius)
                            .fill(Color.eeonAccent)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Results

    private var resultsScreen: some View {
        VStack(spacing: EEONLayout.standard) {
            Spacer()

            Image(systemName: missed.isEmpty ? "checkmark.seal.fill" : "arrow.triangle.2.circlepath")
                .font(.system(size: 52))
                .foregroundStyle(Color.eeonAccent)

            Text(missed.isEmpty ? "All of them." : "\(correctCount) of \(questions.count)")
                .font(.title2.weight(.bold))
                .foregroundStyle(.eeonTextPrimary)

            Text(missed.isEmpty
                 ? "You got every question on this note."
                 : "\(missed.count) to go back over.")
                .font(EEONType.body)
                .foregroundStyle(.eeonTextSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            if !missed.isEmpty {
                Button {
                    startSecondPass()
                } label: {
                    Text("Practise the \(missed.count) I missed")
                        .font(EEONType.control)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 52)
                        .background(
                            RoundedRectangle(cornerRadius: EEONLayout.chipRadius)
                                .fill(Color.eeonAccent)
                        )
                }
                .buttonStyle(.plain)
            }

            Button {
                restart()
            } label: {
                Text("Start over")
                    .font(EEONType.control)
                    .foregroundStyle(.eeonTextPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
                    .background(
                        RoundedRectangle(cornerRadius: EEONLayout.chipRadius)
                            .fill(Color.eeonCard)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: EEONLayout.chipRadius)
                            .strokeBorder(Color.eeonTextTertiary.opacity(0.3), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(EEONLayout.screenMargin)
    }

    // MARK: - Flow

    private func advance(gotIt: Bool) {
        if let question = current {
            if gotIt {
                // Only the FIRST pass counts toward the score, so a second-pass
                // win can't inflate the number above what you actually knew.
                if !isSecondPass { correctCount += 1 }
                missed.removeAll { $0.id == question.id }
            } else if !missed.contains(where: { $0.id == question.id }) {
                missed.append(question)
            }
        }

        withAnimation(.easeInOut(duration: 0.18)) {
            isRevealed = false
            if index + 1 >= queue.count {
                isFinished = true
            } else {
                index += 1
            }
        }
    }

    private func startSecondPass() {
        queue = missed.shuffled()
        index = 0
        isRevealed = false
        isSecondPass = true
        isFinished = false
    }

    private func restart() {
        queue = questions.shuffled()
        index = 0
        isRevealed = false
        missed = []
        correctCount = 0
        isSecondPass = false
        isFinished = false
    }
}
