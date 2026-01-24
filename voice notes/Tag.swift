//
//  Tag.swift
//  voice notes
//

import Foundation
import SwiftData

@Model
final class Tag {
    var id: UUID
    var name: String
    var colorHex: String

    var notes: [Note]

    init(name: String, colorHex: String = "007AFF") {
        self.id = UUID()
        self.name = name
        self.colorHex = colorHex
        self.notes = []
    }
}
