//
//  FirstClarityView.swift
//  voice notes
//
//  First-run experience - next step is the HERO, everything else is context
//

import SwiftUI

struct FirstClarityView: View {
    @Bindable var note: Note
    let onComplete: () -> Void

    @State private var showPaywall = false
    @State private var showUsageExplainer = false
    @State private var selectedDate = Date()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 36))
                            .foregroundStyle(.blue)

                        Text("Your thought, clarified")
                            .font(.title2.weight(.bold))
                    }
                    .padding(.top, 24)

                    // COLLAPSED CONTEXT (secondary, not the focus)
                    VStack(spacing: 10) {
                        // Intent badge - small
                        HStack(spacing: 6) {
                            Image(systemName: note.intent.icon)
                                .font(.caption)
                            Text(note.intent.rawValue)
                                .font(.caption.weight(.medium))
                        }
                        .foregroundStyle(note.intent.color)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(note.intent.color.opacity(0.15))
                        .cornerRadius(12)

                        // Subject - one line
                        if let subject = note.extractedSubject {
                            let actionText = subject.action != nil ? " \u{2192} \(subject.action!)" : ""
                            Text("\(subject.topic)\(actionText)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.horizontal)

                    // HERO: Next step (prominent, actionable)
                    VStack(spacing: 16) {
                        Text("Here's what you need to do:")
                            .font(.headline)
                            .foregroundStyle(.primary)

                        // Big, actionable next step card with resolution UI
                        NextStepHeroCard(
                            note: note,
                            selectedDate: $selectedDate,
                            onResolve: { resolution in
                                note.resolveNextStep(with: resolution)
                                UsageService.shared.useResolution()

                                if UsageService.shared.shouldShowPaywall() {
                                    showPaywall = true
                                } else {
                                    onComplete()
                                }
                            }
                        )
                    }
                    .padding(20)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(16)
                    .padding(.horizontal)

                    Spacer().frame(height: 20)

                    // Tappable usage counter -> explainer sheet
                    Button {
                        showUsageExplainer = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "info.circle")
                                .font(.caption)
                            Text("\(UsageService.shared.freeNotesUsed) of \(UsageService.freeNoteLimit) free notes used")
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 32)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        onComplete()
                    }
                }
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(onDismiss: onComplete)
        }
        .sheet(isPresented: $showUsageExplainer) {
            UsageExplainerView()
        }
    }
}

// MARK: - Next Step Hero Card

struct NextStepHeroCard: View {
    @Bindable var note: Note
    @Binding var selectedDate: Date
    let onResolve: (String) -> Void

    @State private var showDatePicker = false
    @State private var contactName = ""
    @State private var decisionText = ""

    private var nextStep: String { note.suggestedNextStep ?? "Review this note" }
    private var stepType: NextStepType { note.nextStepType }

    var body: some View {
        VStack(spacing: 16) {
            // The next step text
            HStack(spacing: 12) {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)

                Text(nextStep)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)

                Spacer()
            }

            Divider()

            // Resolution UI based on type
            switch stepType {
            case .date:
                HeroDateResolution(
                    selectedDate: $selectedDate,
                    showDatePicker: $showDatePicker,
                    onResolve: onResolve
                )

            case .contact:
                HeroContactResolution(
                    contactName: $contactName,
                    onResolve: onResolve
                )

            case .decision:
                HeroDecisionResolution(
                    decisionText: $decisionText,
                    onResolve: onResolve
                )

            case .simple:
                HeroSimpleResolution(onResolve: { onResolve("Done") })
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
    }
}

// MARK: - Hero Date Resolution

struct HeroDateResolution: View {
    @Binding var selectedDate: Date
    @Binding var showDatePicker: Bool
    let onResolve: (String) -> Void

    private var quickDates: [(String, Date)] {
        let calendar = Calendar.current
        let today = Date()
        return [
            ("Today", today),
            ("Tomorrow", calendar.date(byAdding: .day, value: 1, to: today)!),
            ("Next Week", calendar.date(byAdding: .weekOfYear, value: 1, to: today)!)
        ]
    }

    var body: some View {
        VStack(spacing: 12) {
            // Quick date options
            HStack(spacing: 8) {
                ForEach(quickDates, id: \.0) { label, date in
                    Button(action: {
                        let formatter = DateFormatter()
                        formatter.dateStyle = .medium
                        onResolve(formatter.string(from: date))
                    }) {
                        Text(label)
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color.blue)
                            .foregroundStyle(.white)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }

            Button(action: { showDatePicker.toggle() }) {
                HStack {
                    Image(systemName: "calendar")
                    Text("Pick a specific date")
                }
                .font(.subheadline)
                .foregroundStyle(.blue)
            }

            if showDatePicker {
                DatePicker("", selection: $selectedDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .padding(8)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(8)

                Button(action: {
                    let formatter = DateFormatter()
                    formatter.dateStyle = .medium
                    onResolve(formatter.string(from: selectedDate))
                }) {
                    Text("Confirm Date")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Hero Contact Resolution

struct HeroContactResolution: View {
    @Binding var contactName: String
    let onResolve: (String) -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                TextField("Who did you contact?", text: $contactName)
                    .textFieldStyle(.roundedBorder)

                Button(action: {
                    let resolution = contactName.isEmpty ? "Contacted" : "Sent to \(contactName)"
                    onResolve(resolution)
                }) {
                    Text("Done")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }

            // Quick action
            Button(action: { onResolve("Sent") }) {
                Text("Just mark as sent")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }
        }
    }
}

// MARK: - Hero Decision Resolution

struct HeroDecisionResolution: View {
    @Binding var decisionText: String
    let onResolve: (String) -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                TextField("What did you decide?", text: $decisionText)
                    .textFieldStyle(.roundedBorder)

                Button(action: {
                    let resolution = decisionText.isEmpty ? "Decided" : "Decided: \(decisionText)"
                    onResolve(resolution)
                }) {
                    Text("Done")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }

            // Quick action
            Button(action: { onResolve("Decision made") }) {
                Text("Just mark as decided")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }
        }
    }
}

// MARK: - Hero Simple Resolution

struct HeroSimpleResolution: View {
    let onResolve: () -> Void

    var body: some View {
        Button(action: { onResolve() }) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                Text("Mark as Done")
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.green)
            .foregroundStyle(.white)
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    FirstClarityView(
        note: {
            let note = Note(title: "Board Meeting", content: "Move the board meeting to next week")
            note.intentType = "Action"
            note.extractedSubjectJSON = "{\"topic\":\"Board Meeting\",\"action\":\"Reschedule to next week\"}"
            note.suggestedNextStep = "Pick a date for the board meeting"
            note.nextStepTypeRaw = "date"
            return note
        }(),
        onComplete: {}
    )
}
