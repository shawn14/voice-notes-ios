//
//  Note.swift
//  voice notes
//

import Foundation
import SwiftData

@Model
final class Note {
    var id: UUID
    var title: String
    var content: String
    var transcript: String?
    var audioFileName: String?
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .nullify, inverse: \Tag.notes)
    var tags: [Tag]

    init(
        title: String = "",
        content: String = "",
        transcript: String? = nil,
        audioFileName: String? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.content = content
        self.transcript = transcript
        self.audioFileName = audioFileName
        self.createdAt = Date()
        self.updatedAt = Date()
        self.tags = []
    }

    var displayTitle: String {
        if !title.isEmpty { return title }
        if !content.isEmpty { return String(content.prefix(50)) }
        if let transcript = transcript, !transcript.isEmpty {
            return String(transcript.prefix(50))
        }
        return "Untitled Note"
    }

    var hasAudio: Bool {
        audioFileName != nil
    }

    var audioURL: URL? {
        guard let fileName = audioFileName else { return nil }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(fileName)
    }
}
