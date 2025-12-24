//
//  IndexingService.swift
//  File indexing service
//

import Foundation
import SwiftUI

struct IndexingError: Identifiable {
    let id = UUID()
    let filePath: String
    let fileName: String
    let errorMessage: String
}

actor IndexingService {
    static let shared = IndexingService()

    private let database = VectorDatabase()
    private let fileManager = FileManager.default
    private let ocrService = VisionOCRService.shared
    private let pdfExtractor = PDFTextExtractor.shared
    private let officeExtractor = OfficeDocumentExtractor.shared

    private var errors: [IndexingError] = []

    private init() {}

    // Get settings on main actor
    private func shouldSkipCodeFiles() async -> Bool {
        await MainActor.run {
            AppSettings.shared.skipCodeFiles
        }
    }

    private func shouldSkipImages() async -> Bool {
        await MainActor.run {
            AppSettings.shared.skipImages
        }
    }

    private func getMaxFileSize() async -> Int {
        await MainActor.run {
            AppSettings.shared.maxFileSizeBytes
        }
    }

    private func getMaxDatabaseSize() async -> Int {
        await MainActor.run {
            AppSettings.shared.maxDatabaseSizeBytes
        }
    }

    /// Index a directory recursively
    func indexDirectory(_ url: URL, onProgress: (@Sendable (Int, Int, String) -> Void)? = nil) async -> Int {
        print("📂 Starting indexing of: \(url.path)")

        var indexedCount = 0

        // Security: Canonicalize base path for validation
        guard let basePath = url.path.canonicalizedPath() else {
            print("⚠️ Failed to canonicalize base path")
            return 0
        }

        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            print("⚠️ Failed to enumerate directory: \(url.path)")
            return 0
        }

        // Check settings
        let skipCode = await shouldSkipCodeFiles()
        let skipImages = await shouldSkipImages()
        let maxFileSize = await getMaxFileSize()
        let maxDatabaseSize = await getMaxDatabaseSize()
        print("📋 Skip code files: \(skipCode)")
        print("📋 Skip images: \(skipImages)")
        print("📋 Max file size: \(ByteCountFormatter.string(fromByteCount: Int64(maxFileSize), countStyle: .file))")

        // Check current database size
        let currentDbSize = await database.getStats().totalSize
        print("📊 Current database size: \(ByteCountFormatter.string(fromByteCount: Int64(currentDbSize), countStyle: .file))")

        // Collect all files (text, images, PDFs, and Office documents)
        var filesToIndex: [(URL, String)] = []
        var totalSkippedSize = 0
        var skippedLargeFiles = 0

        while let element = enumerator.nextObject() {
            // Check for cancellation
            if Task.isCancelled {
                print("⚠️ Indexing cancelled during file collection")
                return indexedCount
            }

            guard let fileURL = element as? URL else { continue }

            // Skip node_modules and common directories (always)
            if shouldSkipDirectory(fileURL) {
                enumerator.skipDescendants() // Don't traverse into this directory
                continue
            }

            // Skip common documentation files (always)
            if isCommonDocFile(fileURL) {
                continue // Silent skip - README, CHANGELOG, LICENSE
            }

            // Skip code files early if setting is enabled (before any processing)
            if skipCode && isCodeFile(fileURL) {
                continue // Silent skip - no logging
            }

            // Skip images early if setting is enabled (before OCR processing)
            if skipImages && VisionOCRService.isImageFile(fileURL) {
                continue // Silent skip - no logging
            }

            // Security: Validate path is within base directory
            guard let filePath = fileURL.path.canonicalizedPath(),
                  filePath.hasPrefix(basePath) else {
                print("⚠️ Skipping file outside base directory: \(fileURL.path)")
                continue
            }

            // Security: Check file size before reading
            guard let fileAttributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
                  let fileSize = fileAttributes[.size] as? Int else {
                print("⚠️ Could not get file size for: \(fileURL.lastPathComponent)")
                continue
            }

            // Enforce file size limit
            if fileSize > maxFileSize {
                totalSkippedSize += fileSize
                skippedLargeFiles += 1
                let errorMsg = "File too large: \(ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)) exceeds limit of \(ByteCountFormatter.string(fromByteCount: Int64(maxFileSize), countStyle: .file))"
                print("⏭️ \(errorMsg)")
                errors.append(IndexingError(filePath: fileURL.path, fileName: fileURL.lastPathComponent, errorMessage: errorMsg))
                continue
            }

            // Check database size limit (with estimated overhead per chunk)
            let estimatedChunks = max(1, fileSize / 512)
            let estimatedEmbeddingSize = estimatedChunks * 384 * 4 // 384 dimensions * 4 bytes per float
            let estimatedTotalSize = currentDbSize + estimatedEmbeddingSize

            if estimatedTotalSize > maxDatabaseSize {
                let errorMsg = "Database size limit reached: \(ByteCountFormatter.string(fromByteCount: Int64(currentDbSize), countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: Int64(maxDatabaseSize), countStyle: .file))"
                print("⚠️ \(errorMsg)")
                errors.append(IndexingError(filePath: fileURL.path, fileName: fileURL.lastPathComponent, errorMessage: errorMsg))
                break // Stop indexing entirely
            }

            // Check if it's a text file, image, PDF, or Office document
            if isTextFile(fileURL) {
                // Process text file with error handling
                do {
                    let content = try String(contentsOf: fileURL, encoding: .utf8)
                    guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        print("⏭️ Skipping empty file: \(fileURL.lastPathComponent)")
                        continue
                    }
                    filesToIndex.append((fileURL, content))
                } catch {
                    let errorMsg = "Failed to read text file: \(error.localizedDescription)"
                    print("⚠️ \(errorMsg)")
                    errors.append(IndexingError(filePath: fileURL.path, fileName: fileURL.lastPathComponent, errorMessage: errorMsg))
                }
            } else if VisionOCRService.isImageFile(fileURL) {
                // Process image file with OCR and error handling
                do {
                    let extractedText = try await ocrService.extractText(from: fileURL)
                    guard !extractedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        print("⏭️ Skipping image with no text: \(fileURL.lastPathComponent)")
                        continue
                    }
                    filesToIndex.append((fileURL, extractedText))
                } catch {
                    let errorMsg = "Failed to extract text from image: \(error.localizedDescription)"
                    print("⚠️ \(errorMsg)")
                    errors.append(IndexingError(filePath: fileURL.path, fileName: fileURL.lastPathComponent, errorMessage: errorMsg))
                }
            } else if PDFTextExtractor.isPDFFile(fileURL) {
                // Process PDF file with error handling
                do {
                    let extractedText = try await pdfExtractor.extractText(from: fileURL)
                    guard !extractedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        print("⏭️ Skipping PDF with no text: \(fileURL.lastPathComponent)")
                        continue
                    }
                    filesToIndex.append((fileURL, extractedText))
                } catch {
                    let errorMsg = "Failed to extract text from PDF: \(error.localizedDescription)"
                    print("⚠️ \(errorMsg)")
                    errors.append(IndexingError(filePath: fileURL.path, fileName: fileURL.lastPathComponent, errorMessage: errorMsg))
                }
            } else if OfficeDocumentExtractor.isOfficeFile(fileURL) {
                // Process Office document with error handling
                do {
                    let extractedText = try await officeExtractor.extractText(from: fileURL)
                    guard !extractedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        print("⏭️ Skipping Office file with no text: \(fileURL.lastPathComponent)")
                        continue
                    }
                    filesToIndex.append((fileURL, extractedText))
                } catch {
                    let errorMsg = "Failed to extract text from Office file: \(error.localizedDescription)"
                    print("⚠️ \(errorMsg)")
                    errors.append(IndexingError(filePath: fileURL.path, fileName: fileURL.lastPathComponent, errorMessage: errorMsg))
                }
            }
        }

        print("📊 Found \(filesToIndex.count) files to index")
        if skippedLargeFiles > 0 {
            print("⏭️ Skipped \(skippedLargeFiles) files exceeding size limit (total: \(ByteCountFormatter.string(fromByteCount: Int64(totalSkippedSize), countStyle: .file)))")
        }

        // Index all files (CoreML embedding service handles all languages automatically)
        print("📝 Indexing files...")
        let totalFiles = filesToIndex.count
        for (index, (fileURL, content)) in filesToIndex.enumerated() {
            // Check for cancellation before processing each file
            if Task.isCancelled {
                print("⚠️ Indexing cancelled at file \(index + 1)/\(totalFiles)")
                return indexedCount
            }

            // Report progress
            onProgress?(index + 1, totalFiles, fileURL.lastPathComponent)

            if await database.addDocument(filePath: fileURL, content: content) {
                indexedCount += 1
            }
        }

        print("✅ Indexing complete: \(indexedCount) files indexed")
        return indexedCount
    }

    /// Search for documents
    func search(query: String, limit: Int = 10) async -> (results: [SearchResult], totalMatches: Int) {
        return await database.search(query: query, limit: limit)
    }

    /// Get full document content by combining all chunks
    func getFullDocument(filePath: URL) async -> String? {
        return await database.getFullDocument(filePath: filePath)
    }

    /// Get database statistics
    func getStats() async -> (count: Int, totalSize: Int) {
        await database.getStats()
    }

    /// Clear database
    func clear() async {
        await database.clear()
    }

    /// Get indexing errors
    func getErrors() -> [IndexingError] {
        return errors
    }

    /// Clear indexing errors
    func clearErrors() {
        errors.removeAll()
    }

    /// Get all indexed files grouped by file
    func getIndexedFiles() async -> [(id: UUID, filePath: URL, fileName: String, language: String, chunkCount: Int, fileSize: Int)] {
        await database.getIndexedFilesSummary()
    }

    /// Add a single document (for progress reporting from UI)
    func addDocument(filePath: URL, content: String) async -> Bool {
        // Check if it's an image file
        if VisionOCRService.isImageFile(filePath) {
            // Extract text from image with error handling
            do {
                let extractedText = try await ocrService.extractText(from: filePath)
                guard !extractedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    print("⏭️ Skipping image with no text: \(filePath.lastPathComponent)")
                    return false
                }
                return await database.addDocument(filePath: filePath, content: extractedText)
            } catch {
                print("⚠️ Failed to extract text from image \(filePath.lastPathComponent): \(error)")
                return false
            }
        } else if PDFTextExtractor.isPDFFile(filePath) {
            // Extract text from PDF with error handling
            do {
                let extractedText = try await pdfExtractor.extractText(from: filePath)
                guard !extractedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    print("⏭️ Skipping PDF with no text: \(filePath.lastPathComponent)")
                    return false
                }
                return await database.addDocument(filePath: filePath, content: extractedText)
            } catch {
                print("⚠️ Failed to extract text from PDF \(filePath.lastPathComponent): \(error)")
                return false
            }
        } else if OfficeDocumentExtractor.isOfficeFile(filePath) {
            // Extract text from Office document with error handling
            do {
                let extractedText = try await officeExtractor.extractText(from: filePath)
                guard !extractedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    print("⏭️ Skipping Office file with no text: \(filePath.lastPathComponent)")
                    return false
                }
                return await database.addDocument(filePath: filePath, content: extractedText)
            } catch {
                print("⚠️ Failed to extract text from Office file \(filePath.lastPathComponent): \(error)")
                return false
            }
        }

        // Regular text file
        return await database.addDocument(filePath: filePath, content: content)
    }

    /// Remove orphaned files (files that no longer exist on disk)
    func cleanupOrphanedFiles() async -> Int {
        let indexedFiles = await getIndexedFiles()
        var removedCount = 0

        for file in indexedFiles {
            // Check if file still exists
            if !fileManager.fileExists(atPath: file.filePath.path) {
                print("🗑️ Removing orphaned file: \(file.fileName)")
                _ = await database.deleteDocument(filePath: file.filePath)
                removedCount += 1
            }
        }

        if removedCount > 0 {
            print("✅ Cleaned up \(removedCount) orphaned file(s)")
        }

        return removedCount
    }

    // MARK: - Private Helpers

    private func isTextFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        let textExtensions = [
            "txt", "md", "markdown",
            "swift", "py", "js", "ts", "java", "cpp", "c", "h",
            "json", "xml", "yml", "yaml",
            "html", "css", "scss",
            "sh", "bash", "zsh",
            "log", "csv"
        ]
        return textExtensions.contains(ext)
    }

    private func isCodeFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        let codeExtensions = [
            "swift", "py", "js", "ts", "tsx", "jsx",
            "java", "kt", "kts",
            "cpp", "c", "h", "hpp", "cc", "cxx",
            "cs", "go", "rs", "rb",
            "php", "pl", "r", "scala", "m", "mm",
            "sh", "bash", "zsh", "fish",
            "html", "css", "scss", "sass", "less",
            "json", "xml", "yml", "yaml", "toml"
        ]
        return codeExtensions.contains(ext)
    }

    /// Check if this is a common documentation file that should always be skipped
    private func isCommonDocFile(_ url: URL) -> Bool {
        let fileName = url.lastPathComponent.lowercased()
        let baseName = url.deletingPathExtension().lastPathComponent.lowercased()

        // Match files like: README.md, README.txt, readme, CHANGELOG.md, LICENSE, etc.
        let docPrefixes = ["readme", "changelog", "license", "contributing", "authors"]

        return docPrefixes.contains { prefix in
            baseName == prefix || fileName.hasPrefix(prefix + ".")
        }
    }

    /// Check if this directory should be skipped (node_modules, etc.)
    private func shouldSkipDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return false
        }

        let dirName = url.lastPathComponent.lowercased()

        // Common directories to skip
        let skipDirs = [
            "node_modules",      // Node.js packages
            ".git",              // Git repository
            ".svn",              // SVN repository
            ".hg",               // Mercurial repository
            "vendor",            // PHP/Ruby dependencies
            "venv",              // Python virtual environment
            ".venv",             // Python virtual environment
            "env",               // Python virtual environment
            "__pycache__",       // Python cache
            ".pytest_cache",     // Pytest cache
            ".idea",             // JetBrains IDE
            ".vscode",           // VS Code
            "build",             // Build output
            "dist",              // Distribution output
            "target",            // Maven/Rust build
            ".next",             // Next.js build
            ".nuxt",             // Nuxt.js build
            "coverage",          // Code coverage
            ".nyc_output",       // NYC coverage
        ]

        return skipDirs.contains(dirName)
    }
}

// MARK: - Path Security Extension

private extension String {
    /// Canonicalize path to resolve symlinks and .. components
    func canonicalizedPath() -> String? {
        let standardized = (self as NSString).standardizingPath
        // Resolve symlinks if file exists
        if FileManager.default.fileExists(atPath: standardized) {
            return (standardized as NSString).resolvingSymlinksInPath
        }
        // For non-existent paths, just standardize
        return standardized
    }
}
