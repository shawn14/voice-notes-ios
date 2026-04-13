//
//  PDFExtractionService.swift
//  voice notes
//
//  Extracts text from PDF files using PDFKit with Vision OCR fallback
//  for scanned documents. Caps output at 5000 words.
//

import Foundation
import PDFKit
import Vision
import CoreGraphics

struct ExtractedDocument {
    let text: String
    let title: String
    let pageCount: Int
    let wasOCR: Bool
}

enum PDFExtractionError: LocalizedError {
    case cannotLoadPDF
    case noTextExtracted
    case ocrFailed(String)

    var errorDescription: String? {
        switch self {
        case .cannotLoadPDF: return "Could not open the PDF"
        case .noTextExtracted: return "No readable text found in the PDF"
        case .ocrFailed(let msg): return "OCR failed: \(msg)"
        }
    }
}

actor PDFExtractionService {
    static let shared = PDFExtractionService()
    private let maxWords = 5000

    func extractText(from url: URL) async throws -> ExtractedDocument {
        guard let document = PDFDocument(url: url) else {
            throw PDFExtractionError.cannotLoadPDF
        }

        let pageCount = document.pageCount
        let title = url.deletingPathExtension().lastPathComponent

        // Try PDFKit text extraction first
        if let pdfKitText = extractWithPDFKit(document: document), !pdfKitText.isEmpty {
            let capped = capWords(pdfKitText)
            return ExtractedDocument(text: capped, title: title, pageCount: pageCount, wasOCR: false)
        }

        // Fallback to Vision OCR for scanned documents
        let ocrText = try await extractWithVisionOCR(document: document)
        guard !ocrText.isEmpty else {
            throw PDFExtractionError.noTextExtracted
        }
        let capped = capWords(ocrText)
        return ExtractedDocument(text: capped, title: title, pageCount: pageCount, wasOCR: true)
    }

    private func extractWithPDFKit(document: PDFDocument) -> String? {
        var pages: [String] = []
        var totalChars = 0

        for i in 0..<document.pageCount {
            guard let page = document.page(at: i),
                  let text = page.string, !text.isEmpty else { continue }
            pages.append(text)
            totalChars += text.count
        }

        // If average chars per page is very low, likely a scanned doc
        let avgCharsPerPage = document.pageCount > 0 ? totalChars / document.pageCount : 0
        if avgCharsPerPage < 50 {
            return nil
        }

        return pages.joined(separator: "\n\n")
    }

    private func extractWithVisionOCR(document: PDFDocument) async throws -> String {
        var pages: [String] = []

        for i in 0..<document.pageCount {
            guard let page = document.page(at: i) else { continue }

            let pageRect = page.bounds(for: .mediaBox)
            let scale: CGFloat = 2.0
            let width = Int(pageRect.width * scale)
            let height = Int(pageRect.height * scale)

            guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(
                    data: nil,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: 0,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else { continue }

            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.scaleBy(x: scale, y: scale)
            page.draw(with: .mediaBox, to: context)

            guard let cgImage = context.makeImage() else { continue }

            let text = try await recognizeText(in: cgImage)
            if !text.isEmpty {
                pages.append(text)
            }
        }

        return pages.joined(separator: "\n\n")
    }

    private func recognizeText(in image: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: PDFExtractionError.ocrFailed(error.localizedDescription))
                    return
                }

                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let text = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
                continuation.resume(returning: text)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: PDFExtractionError.ocrFailed(error.localizedDescription))
            }
        }
    }

    private func capWords(_ text: String) -> String {
        let words = text.split(separator: " ", omittingEmptySubsequences: true)
        if words.count <= maxWords { return text }
        return words.prefix(maxWords).joined(separator: " ")
    }
}
