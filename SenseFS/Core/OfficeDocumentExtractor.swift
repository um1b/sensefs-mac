//
//  OfficeDocumentExtractor.swift
//  Text extraction from Microsoft Office files (docx, xlsx, pptx)
//

import Foundation
import ZIPFoundation

actor OfficeDocumentExtractor {
    static let shared = OfficeDocumentExtractor()

    private init() {}

    /// Extract text from an Office document (docx, xlsx, pptx)
    func extractText(from fileURL: URL) async throws -> String {
        let ext = fileURL.pathExtension.lowercased()

        switch ext {
        case "docx":
            return try await extractFromDocx(fileURL)
        case "xlsx":
            return try await extractFromXlsx(fileURL)
        case "pptx":
            return try await extractFromPptx(fileURL)
        default:
            throw OfficeError.unsupportedFormat
        }
    }

    // MARK: - DOCX Extraction

    private func extractFromDocx(_ fileURL: URL) async throws -> String {
        let archive = try Archive(url: fileURL, accessMode: .read)


        // DOCX structure: word/document.xml contains the main text
        guard let documentEntry = archive["word/document.xml"] else {
            throw OfficeError.malformedDocument
        }

        var xmlData = Data()
        _ = try archive.extract(documentEntry) { data in
            xmlData.append(data)
        }

        // Parse XML with UTF-8 encoding
        guard let xmlString = String(data: xmlData, encoding: .utf8) else {
            throw OfficeError.encodingError
        }

        // Extract text from XML (between <w:t> tags)
        let text = extractTextFromXML(xmlString, tagName: "w:t")

        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            print("⚠️ No text found in DOCX: \(fileURL.lastPathComponent)")
        } else {
            let wordCount = text.split(separator: " ").count
            print("📝 Extracted ~\(wordCount) words from DOCX: \(fileURL.lastPathComponent)")
        }

        return text
    }

    // MARK: - XLSX Extraction

    private func extractFromXlsx(_ fileURL: URL) async throws -> String {
        let archive = try Archive(url: fileURL, accessMode: .read)


        var allText = ""
        var sheetCount = 0

        // XLSX structure: xl/sharedStrings.xml contains shared strings
        // xl/worksheets/sheet*.xml contains the actual data

        // First, extract shared strings (used by cells)
        var sharedStrings: [String] = []
        if let sharedStringsEntry = archive["xl/sharedStrings.xml"] {
            var xmlData = Data()
            _ = try archive.extract(sharedStringsEntry) { data in
                xmlData.append(data)
            }

            if let xmlString = String(data: xmlData, encoding: .utf8) {
                sharedStrings = extractTextFromXML(xmlString, tagName: "t")
                    .components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
        }

        // Extract text from worksheets
        for entry in archive where entry.path.hasPrefix("xl/worksheets/sheet") && entry.path.hasSuffix(".xml") {
            var xmlData = Data()
            _ = try archive.extract(entry) { data in
                xmlData.append(data)
            }

            guard let xmlString = String(data: xmlData, encoding: .utf8) else { continue }

            // Extract cell values (both inline strings and shared strings references)
            let cellText = extractTextFromXML(xmlString, tagName: "v")

            if !cellText.isEmpty {
                if sheetCount > 0 {
                    allText += "\n\n--- Sheet \(sheetCount + 1) ---\n\n"
                }
                allText += cellText
                sheetCount += 1
            }
        }

        // If we have shared strings, include them as well
        if !sharedStrings.isEmpty {
            if !allText.isEmpty {
                allText += "\n\n"
            }
            allText += sharedStrings.joined(separator: "\n")
        }

        if allText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            print("⚠️ No text found in XLSX: \(fileURL.lastPathComponent)")
        } else {
            print("📊 Extracted text from \(sheetCount) sheets in XLSX: \(fileURL.lastPathComponent)")
        }

        return allText
    }

    // MARK: - PPTX Extraction

    private func extractFromPptx(_ fileURL: URL) async throws -> String {
        let archive = try Archive(url: fileURL, accessMode: .read)


        var allText = ""
        var slideCount = 0

        // PPTX structure: ppt/slides/slide*.xml contains slide content
        let slideEntries = archive.filter {
            $0.path.hasPrefix("ppt/slides/slide") && $0.path.hasSuffix(".xml")
        }.sorted { $0.path < $1.path }

        for entry in slideEntries {
            var xmlData = Data()
            _ = try archive.extract(entry) { data in
                xmlData.append(data)
            }

            guard let xmlString = String(data: xmlData, encoding: .utf8) else { continue }

            // Extract text from <a:t> tags (text runs in PowerPoint)
            let slideText = extractTextFromXML(xmlString, tagName: "a:t")

            if !slideText.isEmpty {
                if slideCount > 0 {
                    allText += "\n\n--- Slide \(slideCount + 1) ---\n\n"
                }
                allText += slideText
                slideCount += 1
            }
        }

        if allText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            print("⚠️ No text found in PPTX: \(fileURL.lastPathComponent)")
        } else {
            print("📊 Extracted text from \(slideCount) slides in PPTX: \(fileURL.lastPathComponent)")
        }

        return allText
    }

    // MARK: - XML Parsing Helper

    private func extractTextFromXML(_ xmlString: String, tagName: String) -> String {
        var results: [String] = []

        // Use regex to extract text between tags
        // Pattern: <tagName[^>]*>(.*?)</tagName>
        let pattern = "<\(tagName)[^>]*>(.*?)</\(tagName)>"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return ""
        }

        let nsString = xmlString as NSString
        let matches = regex.matches(in: xmlString, range: NSRange(location: 0, length: nsString.length))

        for match in matches {
            if match.numberOfRanges > 1 {
                let range = match.range(at: 1)
                let text = nsString.substring(with: range)

                // Decode XML entities
                let decoded = decodeXMLEntities(text)
                if !decoded.isEmpty {
                    results.append(decoded)
                }
            }
        }

        return results.joined(separator: "\n")
    }

    // MARK: - XML Entity Decoding

    private func decodeXMLEntities(_ text: String) -> String {
        var result = text

        // Common XML entities
        let entities: [(String, String)] = [
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&amp;", "&"),
            ("&quot;", "\""),
            ("&apos;", "'"),
            ("&nbsp;", " ")
        ]

        for (entity, replacement) in entities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }

        // Handle numeric character references (&#...; and &#x...;)
        // Match &#digits; or &#xhex;
        let numericPattern = "&#(x)?([0-9a-fA-F]+);"
        if let regex = try? NSRegularExpression(pattern: numericPattern) {
            let nsString = result as NSString
            let matches = regex.matches(in: result, range: NSRange(location: 0, length: nsString.length))

            // Process in reverse to maintain indices
            for match in matches.reversed() {
                let fullRange = match.range
                let isHex = match.range(at: 1).location != NSNotFound
                let numberRange = match.range(at: 2)
                let numberString = nsString.substring(with: numberRange)

                if let number = isHex ? Int(numberString, radix: 16) : Int(numberString),
                   let scalar = UnicodeScalar(number) {
                    let character = String(Character(scalar))
                    result = (result as NSString).replacingCharacters(in: fullRange, with: character)
                }
            }
        }

        return result
    }

    // MARK: - File Type Checking

    static func isOfficeFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ["docx", "xlsx", "pptx"].contains(ext)
    }

    static func getFileType(_ url: URL) -> String? {
        let ext = url.pathExtension.lowercased()
        return ["docx", "xlsx", "pptx"].contains(ext) ? ext : nil
    }
}

// MARK: - Errors

enum OfficeError: Error, LocalizedError {
    case invalidFile
    case unsupportedFormat
    case malformedDocument
    case encodingError

    var errorDescription: String? {
        switch self {
        case .invalidFile:
            return "Unable to open Office file (not a valid ZIP archive)"
        case .unsupportedFormat:
            return "Unsupported Office file format"
        case .malformedDocument:
            return "Malformed Office document structure"
        case .encodingError:
            return "Text encoding error (expected UTF-8)"
        }
    }
}
