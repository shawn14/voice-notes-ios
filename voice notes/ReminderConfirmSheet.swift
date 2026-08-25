//
//  ReminderConfirmSheet.swift
//  voice notes
//
//  The confirmation moment after "remind me…": what EEON heard, the date it
//  parsed, one tap to put it in Apple Reminders. The note is already saved
//  underneath; "Just a note" leaves it at that.
//

import SwiftUI
import UIKit

struct ReminderConfirmSheet: View {
    let command: ReminderCommandParser.Command
    let onDone: () -> Void

    @State private var title: String
    @State private var hasDue: Bool
    @State private var due: Date
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var accessDenied = false

    init(command: ReminderCommandParser.Command, onDone: @escaping () -> Void) {
        self.command = command
        self.onDone = onDone
        _title = State(initialValue: command.title)
        _hasDue = State(initialValue: command.due != nil)
        _due = State(initialValue: command.due ?? Self.nextHour())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Reminder", text: $title, axis: .vertical)
                        .font(EEONType.body)
                    Toggle("Due date", isOn: $hasDue.animation())
                    if hasDue {
                        DatePicker("When", selection: $due, displayedComponents: [.date, .hourAndMinute])
                    }
                } header: {
                    Text("Remind me")
                } footer: {
                    Text("You said: \u{201C}\(command.original)\u{201D}")
                        .font(EEONType.meta)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(EEONType.meta)
                            .foregroundStyle(.red)
                        if accessDenied {
                            Button("Open Settings") {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Just a note") { onDone() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Add to Reminders").fontWeight(.semibold)
                        }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(isSaving)
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        accessDenied = false
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let when = hasDue ? due : nil
        Task {
            do {
                try await EventKitSyncService.shared.createReminder(title: cleanTitle, due: when)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                onDone()
            } catch EventKitSyncService.CreateError.accessDenied {
                accessDenied = true
                errorMessage = "EEON doesn't have access to Reminders. Allow it in Settings and try again."
                isSaving = false
            } catch {
                errorMessage = error.localizedDescription
                isSaving = false
            }
        }
    }

    private static func nextHour() -> Date {
        let calendar = Calendar.current
        let inAnHour = Date().addingTimeInterval(3600)
        var comps = calendar.dateComponents([.year, .month, .day, .hour], from: inAnHour)
        comps.minute = 0
        return calendar.date(from: comps) ?? inAnHour
    }
}
