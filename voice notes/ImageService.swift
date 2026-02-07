//
//  ImageService.swift
//  voice notes
//
//  Image attachment management: save, load, and OCR text extraction

import UIKit
import Vision

enum ImageService {
    enum ImageError: LocalizedError {
        case saveFailed
        case loadFailed
        case ocrFailed

        var errorDescription: String? {
            switch self {
            case .saveFailed: return "Failed to save image"
            case .loadFailed: return "Failed to load image"
            case .ocrFailed: return "Failed to extract text from image"
            }
        }
    }

    // MARK: - Save Image

    /// Saves an image to Documents directory and returns the filename
    static func saveImage(_ image: UIImage, noteId: UUID) throws -> String {
        guard let data = image.jpegData(compressionQuality: 0.8) else {
            throw ImageError.saveFailed
        }

        let fileName = "\(noteId.uuidString)_\(UUID().uuidString.prefix(8)).jpg"
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentsURL.appendingPathComponent(fileName)

        do {
            try data.write(to: fileURL)
            return fileName
        } catch {
            throw ImageError.saveFailed
        }
    }

    // MARK: - Load Image

    /// Loads an image from Documents directory by filename
    static func loadImage(fileName: String) -> UIImage? {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentsURL.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return UIImage(contentsOfFile: fileURL.path)
    }

    /// Gets the file URL for an image filename
    static func imageURL(for fileName: String) -> URL {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsURL.appendingPathComponent(fileName)
    }

    // MARK: - Delete Image

    /// Deletes an image from Documents directory
    static func deleteImage(fileName: String) {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentsURL.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - OCR Text Extraction

    /// Extracts text from an image using Vision framework (no API call)
    static func extractText(from image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else {
            throw ImageError.ocrFailed
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: "")
                    return
                }

                let recognizedText = observations.compactMap { observation in
                    observation.topCandidates(1).first?.string
                }.joined(separator: "\n")

                continuation.resume(returning: recognizedText)
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: ImageError.ocrFailed)
            }
        }
    }

    // MARK: - Thumbnail Generation

    /// Creates a thumbnail of the specified size
    static func createThumbnail(from image: UIImage, size: CGSize) -> UIImage? {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
