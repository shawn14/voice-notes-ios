//
//  WebContentService.swift
//  voice notes
//
//  Fetches and extracts readable text content from URLs.
//  Used when processing web articles shared via the share extension.
//

import Foundation

struct WebContent {
    let title: String
    let text: String
    let url: String
}

enum WebContentService {
    enum WebContentError: LocalizedError {
        case invalidURL
        case fetchFailed(String)
        case noContent

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid URL"
            case .fetchFailed(let msg): return "Fetch failed: \(msg)"
            case .noContent: return "No readable content found"
            }
        }
    }

    /// Fetch a URL and extract readable article text.
    /// Caps output at 3000 words to bound extraction + embedding costs.
    static func fetchArticle(from urlString: String) async throws -> WebContent {
        guard let url = URL(string: urlString) else {
            throw WebContentError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw WebContentError.fetchFailed("HTTP \(status)")
        }

        let html = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .ascii)
            ?? ""

        guard !html.isEmpty else {
            throw WebContentError.noContent
        }

        let title = extractTitle(from: html) ?? url.host ?? "Web Article"
        let text = extractReadableText(from: html)

        guard !text.isEmpty else {
            throw WebContentError.noContent
        }

        // Cap at 3000 words
        let words = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let capped = words.prefix(3000).joined(separator: " ")

        return WebContent(title: title, text: capped, url: urlString)
    }

    // MARK: - HTML Extraction

    /// Extract <title> tag content
    private static func extractTitle(from html: String) -> String? {
        guard let titleStart = html.range(of: "<title", options: .caseInsensitive),
              let tagEnd = html.range(of: ">", range: titleStart.upperBound..<html.endIndex),
              let titleEnd = html.range(of: "</title>", options: .caseInsensitive, range: tagEnd.upperBound..<html.endIndex)
        else { return nil }

        let title = String(html[tagEnd.upperBound..<titleEnd.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }

    /// Extract readable text from HTML, preferring <article> or <main> content
    private static func extractReadableText(from html: String) -> String {
        // Try <article> first, then <main>, then <body>
        let contentHTML: String
        if let articleContent = extractTagContent(from: html, tag: "article") {
            contentHTML = articleContent
        } else if let mainContent = extractTagContent(from: html, tag: "main") {
            contentHTML = mainContent
        } else if let bodyContent = extractTagContent(from: html, tag: "body") {
            contentHTML = bodyContent
        } else {
            contentHTML = html
        }

        // Remove script and style tags with their content
        var cleaned = contentHTML
        cleaned = removeTagWithContent(from: cleaned, tag: "script")
        cleaned = removeTagWithContent(from: cleaned, tag: "style")
        cleaned = removeTagWithContent(from: cleaned, tag: "nav")
        cleaned = removeTagWithContent(from: cleaned, tag: "header")
        cleaned = removeTagWithContent(from: cleaned, tag: "footer")

        // Strip remaining HTML tags
        cleaned = cleaned.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)

        // Decode common HTML entities
        cleaned = cleaned.replacingOccurrences(of: "&amp;", with: "&")
        cleaned = cleaned.replacingOccurrences(of: "&lt;", with: "<")
        cleaned = cleaned.replacingOccurrences(of: "&gt;", with: ">")
        cleaned = cleaned.replacingOccurrences(of: "&quot;", with: "\"")
        cleaned = cleaned.replacingOccurrences(of: "&#39;", with: "'")
        cleaned = cleaned.replacingOccurrences(of: "&nbsp;", with: " ")

        // Collapse whitespace
        cleaned = cleaned.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Extract content between opening and closing tags (first match)
    private static func extractTagContent(from html: String, tag: String) -> String? {
        guard let openStart = html.range(of: "<\(tag)", options: .caseInsensitive),
              let openEnd = html.range(of: ">", range: openStart.upperBound..<html.endIndex),
              let closeStart = html.range(of: "</\(tag)>", options: .caseInsensitive, range: openEnd.upperBound..<html.endIndex)
        else { return nil }

        return String(html[openEnd.upperBound..<closeStart.lowerBound])
    }

    /// Remove a tag and all its content (handles multiple occurrences)
    private static func removeTagWithContent(from html: String, tag: String) -> String {
        html.replacingOccurrences(
            of: "<\(tag)[^>]*>[\\s\\S]*?</\(tag)>",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
    }
}
