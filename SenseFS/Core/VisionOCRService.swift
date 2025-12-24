//
//  VisionOCRService.swift
//  Text extraction from images using Vision framework
//

import Foundation
import Vision
import AppKit

actor VisionOCRService {
    static let shared = VisionOCRService()

    private init() {}

    /// Extract text from an image file
    func extractText(from imageURL: URL) async throws -> String {
        // Load image data
        guard let image = NSImage(contentsOf: imageURL) else {
            throw OCRError.invalidImage
        }

        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw OCRError.cgImageConversionFailed
        }

        return try await withCheckedThrowingContinuation { continuation in
            // Create text recognition request
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

                if recognizedText.isEmpty {
                    print("⚠️ No text found in image: \(imageURL.lastPathComponent)")
                } else {
                    let lineCount = recognizedText.components(separatedBy: "\n").count
                    print("📸 Extracted \(lineCount) lines from: \(imageURL.lastPathComponent)")
                }

                continuation.resume(returning: recognizedText)
            }

            // Configure for accuracy and multi-language support
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true

            // Perform OCR
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Extract text from image data
    func extractText(from imageData: Data) async throws -> String {
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
            request.automaticallyDetectsLanguage = true

            let handler = VNImageRequestHandler(data: imageData, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Check if a file is an image format supported by Vision
    static func isImageFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        let supportedExtensions = [
            "jpg", "jpeg", "png", "tiff", "tif",
            "bmp", "gif", "heic", "heif", "webp"
        ]
        return supportedExtensions.contains(ext)
    }
}

// MARK: - Errors

enum OCRError: Error, LocalizedError {
    case invalidImage
    case cgImageConversionFailed
    case noTextFound

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "Unable to load image file"
        case .cgImageConversionFailed:
            return "Failed to convert image to CGImage"
        case .noTextFound:
            return "No text found in image"
        }
    }
}
