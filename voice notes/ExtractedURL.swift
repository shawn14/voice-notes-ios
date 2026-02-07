//
//  ExtractedURL.swift
//  voice notes
//
//  URL Intelligence: Stores detected URLs and their fetched metadata

import Foundation
import SwiftData

@Model
final class ExtractedURL {
    var id: UUID = UUID()
    var url: String = ""
    var title: String?
    var urlDescription: String?
    var siteName: String?
    var imageURL: String?
    var faviconURL: String?
    var fetchedAt: Date?
    var fetchError: String?
    var sourceNoteId: UUID?
    var createdAt: Date = Date()

    init(url: String, sourceNoteId: UUID? = nil) {
        self.id = UUID()
        self.url = url
        self.sourceNoteId = sourceNoteId
        self.createdAt = Date()
    }

    var isFetched: Bool {
        fetchedAt != nil && fetchError == nil
    }

    var hasFailed: Bool {
        fetchError != nil
    }

    var displayTitle: String {
        title ?? siteName ?? url
    }

    var displayHost: String {
        URL(string: url)?.host ?? url
    }
}

