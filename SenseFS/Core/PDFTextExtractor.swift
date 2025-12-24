//
//  PDFTextExtractor.swift
//  Text extraction from PDF files using PDFKit
//

import Foundation
import PDFKit

actor PDFTextExtractor {
    static let shared = PDFTextExtractor()

    private init() {}

    /// Extract text from a PDF file
    func extractText(from pdfURL: URL) async throws -> String {
        guard let pdfDocument = PDFDocument(url: pdfURL) else {
            throw PDFError.invalidPDF
        }

        let pageCount = pdfDocument.pageCount
        guard pageCount > 0 else {
            throw PDFError.emptyPDF
        }

        var allText = ""
        var extractedPages = 0

        // Extract text from each page
        for pageIndex in 0..<pageCount {
            guard let page = pdfDocument.page(at: pageIndex) else { continue }

            if let pageText = page.string {
                // Add page separator for multi-page PDFs
                if !allText.isEmpty {
                    allText += "\n\n--- Page \(pageIndex + 1) ---\n\n"
                }
                allText += pageText
                extractedPages += 1
            }
        }

        if allText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            print("⚠️ No text found in PDF: \(pdfURL.lastPathComponent)")
            throw PDFError.noTextFound
        }

        print("📄 Extracted text from \(extractedPages)/\(pageCount) pages in: \(pdfURL.lastPathComponent)")

        return allText
    }

    /// Extract text from a specific page range
    func extractText(from pdfURL: URL, pages: Range<Int>) async throws -> String {
        guard let pdfDocument = PDFDocument(url: pdfURL) else {
            throw PDFError.invalidPDF
        }

        let pageCount = pdfDocument.pageCount
        var allText = ""

        for pageIndex in pages {
            guard pageIndex < pageCount else { break }
            guard let page = pdfDocument.page(at: pageIndex) else { continue }

            if let pageText = page.string {
                if !allText.isEmpty {
                    allText += "\n\n--- Page \(pageIndex + 1) ---\n\n"
                }
                allText += pageText
            }
        }

        return allText
    }

    /// Get page count of a PDF
    func getPageCount(from pdfURL: URL) -> Int {
        guard let pdfDocument = PDFDocument(url: pdfURL) else { return 0 }
        return pdfDocument.pageCount
    }

    /// Check if a file is a PDF
    static func isPDFFile(_ url: URL) -> Bool {
        return url.pathExtension.lowercased() == "pdf"
    }
}

// MARK: - Errors

enum PDFError: Error, LocalizedError {
    case invalidPDF
    case emptyPDF
    case noTextFound

    var errorDescription: String? {
        switch self {
        case .invalidPDF:
            return "Unable to load PDF file"
        case .emptyPDF:
            return "PDF file has no pages"
        case .noTextFound:
            return "No text found in PDF"
        }
    }
}
