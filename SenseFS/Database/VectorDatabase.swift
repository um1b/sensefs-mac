//
//  VectorDatabase.swift
//  Simple in-memory vector database
//

import Foundation

struct DocumentEntry {
    let id: UUID
    let filePath: URL
    let fileName: String
    let content: String
    let chunkIndex: Int  // Which chunk of the file this is
    let language: String  // Detected language (e.g., "ja", "en")
    let embedding: [Float]
}

actor VectorDatabase {
    private let dbManager = DatabaseManager.shared
    private let embeddingService = CoreMLEmbeddingService.shared
    private let chunker = TextChunker()
    private let spellChecker = SpellChecker()

    /// Helper to get skip code files setting
    @MainActor
    private func shouldSkipCodeFiles() async -> Bool {
        return AppSettings.shared.skipCodeFiles
    }

    /// Helper to get skip images setting
    @MainActor
    private func shouldSkipImages() async -> Bool {
        return AppSettings.shared.skipImages
    }

    /// Get list of code file extensions to exclude
    private func getCodeExtensions() -> [String] {
        return [
            // Programming languages
            "swift", "py", "js", "ts", "jsx", "tsx", "java", "kt", "kts",
            "c", "cpp", "cc", "cxx", "h", "hpp", "cs", "go", "rs", "rb",
            "php", "pl", "lua", "r", "m", "mm", "scala", "sh", "bash",
            "zsh", "fish", "ps1", "psm1", "sql", "dart", "ex", "exs",
            // Config and data files
            "json", "xml", "yaml", "yml", "toml", "ini", "cfg", "conf",
            "plist", "gradle", "cmake", "make", "dockerfile",
            // Web and markup
            "html", "htm", "css", "scss", "sass", "less", "vue", "svelte",
            // Build and package files
            "lock", "podspec", "gemfile", "rakefile", "makefile"
        ]
    }

    /// Add document to database (with chunking and change detection)
    func addDocument(filePath: URL, content: String) async -> Bool {
        let fileName = filePath.lastPathComponent
        let fileNameWithoutExtension = filePath.deletingPathExtension().lastPathComponent

        // Get file attributes for change detection
        let fileManager = FileManager.default
        guard let attributes = try? fileManager.attributesOfItem(atPath: filePath.path),
              let modifiedAt = attributes[.modificationDate] as? Date,
              let fileSize = attributes[.size] as? Int else {
            print("⚠️ Failed to get file attributes for \(fileName)")
            return false
        }

        // Check if file has changed since last indexing
        if let metadata = await dbManager.getFileMetadata(filePath: filePath.path) {
            // File exists in database - check if it changed
            // Use timestamp comparison with 1-second tolerance to handle precision differences
            let timeDifference = abs(metadata.modifiedAt.timeIntervalSince(modifiedAt))
            let sizeMatches = metadata.fileSize == fileSize
            let timeMatches = timeDifference < 1.0 // Within 1 second

            if timeMatches && sizeMatches {
                print("⏭️ Skipping unchanged file: \(fileName)")
                return true // Return true because file is already indexed correctly
            } else {
                print("🔄 File changed, reindexing: \(fileName) (time diff: \(timeDifference)s, size: \(metadata.fileSize) → \(fileSize))")
                // Delete old chunks before reindexing
                _ = await dbManager.deleteDocumentsByPath(filePath.path)
            }
        }

        // Clean filename for better matching
        let cleanFileName = fileNameWithoutExtension
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")

        // Detect language from full content (multilingual model handles all languages)
        let documentLanguage = await embeddingService.detectLanguage(content) ?? "multilingual"
        print("🌐 Detected language for \(fileName): \(documentLanguage)")

        // Chunk the content with overlap (max 512 chars, 1 sentence overlap)
        let chunks = await chunker.chunkText(content, maxChunkSize: 512, overlapSentences: 1)

        // Prepare all texts for batch embedding
        let textsToEmbed = chunks.map { chunk in
            "\(cleanFileName) \(chunk.text)"
        }

        // Use batch embedding for efficiency
        do {
            let embeddings = try await embeddingService.embedBatch(textsToEmbed)

            // Store all chunks in database with metadata
            var successCount = 0
            for (index, chunk) in chunks.enumerated() {
                let success = await dbManager.insertDocument(
                    id: UUID().uuidString,
                    filePath: filePath.path,
                    fileName: fileName,
                    content: chunk.text,
                    chunkIndex: chunk.index,
                    language: documentLanguage,
                    embedding: embeddings[index],
                    modifiedAt: modifiedAt,
                    fileSize: fileSize
                )
                if success {
                    successCount += 1
                }
            }

            if successCount > 0 {
                print("✅ Indexed: \(fileName) (\(successCount) chunks, language: \(documentLanguage))")
                return true
            } else {
                print("⚠️ Failed to index: \(fileName)")
                return false
            }
        } catch {
            print("⚠️ Failed to embed chunks for \(fileName): \(error)")
            return false
        }
    }

    /// Search for similar documents (deduplicated by file with avg/max scores)
    /// Returns tuple of (results limited by limit, total number of matches found)
    func search(query: String, limit: Int = 10, maxDocuments: Int = 50000) async -> (results: [SearchResult], totalMatches: Int) {
        do {
            // First, detect the language by embedding the original query
            let initialResult = try await embeddingService.embed(query)
            let detectedLanguage = initialResult.language
            print("🔍 Query language detected: \(detectedLanguage)")

            // Correct spelling using detected language
            let correctedQuery = spellChecker.correctSpelling(query, language: detectedLanguage)
            let finalQuery = correctedQuery != query ? correctedQuery : query

            if correctedQuery != query {
                print("✏️ Corrected query: '\(query)' → '\(correctedQuery)'")
            }

            // Re-embed with corrected query if it changed
            let queryResult = correctedQuery != query ? try await embeddingService.embed(finalQuery) : initialResult
            let queryEmbedding = queryResult.vector
            _ = queryResult.language

            // Fetch documents from database, excluding code files and/or images if settings enabled
            let skipCodeFiles = await shouldSkipCodeFiles()
            let skipImages = await shouldSkipImages()
            var excludeExtensions: [String] = []

            if skipCodeFiles {
                excludeExtensions.append(contentsOf: getCodeExtensions())
                print("📋 Skip code files enabled - excluding \(getCodeExtensions().count) code extensions")
            }

            if skipImages {
                let imageExtensions = ["jpg", "jpeg", "png", "tiff", "tif", "bmp", "gif", "heic", "heif", "webp"]
                excludeExtensions.append(contentsOf: imageExtensions)
                print("📋 Skip images enabled - excluding \(imageExtensions.count) image extensions")
            }

            var dbDocuments = await dbManager.fetchAllDocuments(excludeExtensions: excludeExtensions)
            print("📊 Fetched \(dbDocuments.count) chunks from database")

            // Safety: Limit documents to prevent memory issues
            if dbDocuments.count > maxDocuments {
                print("⚠️ Database has \(dbDocuments.count) chunks, limiting to \(maxDocuments) most recent")
                // Sort by creation date and take most recent
                dbDocuments = Array(dbDocuments.prefix(maxDocuments))
            }

            // Convert to DocumentEntry for processing
            let documents = dbDocuments.map { doc in
                DocumentEntry(
                    id: UUID(uuidString: doc.id) ?? UUID(),
                    filePath: URL(fileURLWithPath: doc.filePath),
                    fileName: doc.fileName,
                    content: doc.content,
                    chunkIndex: doc.chunkIndex,
                    language: doc.language,
                    embedding: doc.embedding
                )
            }

            // Calculate scores for all chunks with relevance threshold
            var chunkResults: [(doc: DocumentEntry, score: Float)] = []
            var maxScoreSeen: Float = 0
            var minScoreSeen: Float = 1
            let relevanceThreshold: Float = 0.1 // Skip very low scores

            for doc in documents {
                var score = await embeddingService.cosineSimilarity(queryEmbedding, doc.embedding)

                // Skip irrelevant results early
                guard score > relevanceThreshold else { continue }

                maxScoreSeen = max(maxScoreSeen, score)
                minScoreSeen = min(minScoreSeen, score)

                // Boost score if query appears in filename
                let queryLower = query.lowercased()
                let fileNameLower = doc.fileName.lowercased()

                if fileNameLower.contains(queryLower) {
                    // Apply 50% boost for filename match
                    score *= 1.5
                    print("📌 Filename match boost: \(doc.fileName) (\(score))")
                }

                chunkResults.append((doc, score))
            }

            print("📊 Score range: min=\(minScoreSeen), max=\(maxScoreSeen)")
            print("📊 Total chunks scored: \(chunkResults.count)")

        // Group by file path
        var fileGroups: [String: [(doc: DocumentEntry, score: Float)]] = [:]
        for result in chunkResults {
            let path = result.doc.filePath.path
            fileGroups[path, default: []].append(result)
        }

        // Calculate avg and max scores per file, pick best chunk
        var deduplicatedResults: [SearchResult] = []
        for (_, chunks) in fileGroups {
            guard !chunks.isEmpty else { continue }

            // Find best matching chunk (safely unwrap)
            guard let bestChunk = chunks.max(by: { $0.score < $1.score }) else {
                print("⚠️ No chunks found for file group, skipping")
                continue
            }

            // Calculate average and max scores
            let scores = chunks.map { $0.score }
            let avgScore = scores.reduce(0, +) / Float(scores.count)
            let maxScore = scores.max() ?? 0

            deduplicatedResults.append(SearchResult(
                id: bestChunk.doc.id,
                filePath: bestChunk.doc.filePath,
                fileName: bestChunk.doc.fileName,
                content: bestChunk.doc.content,
                chunkIndex: bestChunk.doc.chunkIndex,
                language: bestChunk.doc.language,  // Pass language
                score: maxScore,          // Use max score for sorting
                avgScore: avgScore,        // Store avg for display
                maxScore: maxScore,        // Store max for display
                totalChunks: chunks.count  // How many chunks this file has
            ))
        }

            // Sort by max score
            let sortedResults = deduplicatedResults.sorted { $0.maxScore > $1.maxScore }
            let totalMatches = sortedResults.count

            // Take top-k
            let results = Array(sortedResults.prefix(limit))

            print("📊 Found \(totalMatches) total matches, returning top \(results.count)")
            if let topResult = results.first {
                print("📊 Top result: \(topResult.fileName) with score: \(topResult.maxScore)")
            }

            return (results, totalMatches)
        } catch {
            print("⚠️ Failed to generate query embedding: \(error)")
            return ([], 0)
        }
    }

    /// Retrieve full document content by combining all chunks
    func getFullDocument(filePath: URL) async -> String? {
        let allDocuments = await dbManager.fetchAllDocuments()

        // Filter chunks for this file path and sort by chunk index
        let fileChunks = allDocuments
            .filter { $0.filePath == filePath.path }
            .sorted { $0.chunkIndex < $1.chunkIndex }

        guard !fileChunks.isEmpty else {
            print("⚠️ No chunks found for file: \(filePath.lastPathComponent)")
            return nil
        }

        // Combine all chunks into full document
        let fullContent = fileChunks.map { $0.content }.joined(separator: "\n")

        print("📄 Retrieved full document: \(filePath.lastPathComponent) (\(fileChunks.count) chunks, \(fullContent.count) chars)")

        return fullContent
    }

    /// Get statistics
    func getStats() async -> (count: Int, totalSize: Int) {
        return await dbManager.getStats()
    }

    /// Clear all documents
    func clear() async {
        _ = await dbManager.clearAll()
    }

    /// Delete a document by file path
    func deleteDocument(filePath: URL) async -> Bool {
        return await dbManager.deleteDocumentsByPath(filePath.path)
    }

    /// Get indexed files summary (grouped by file)
    func getIndexedFilesSummary() async -> [(id: UUID, filePath: URL, fileName: String, language: String, chunkCount: Int, fileSize: Int)] {
        let summary = await dbManager.getIndexedFilesSummary()

        return summary.map { entry in
            (
                id: UUID(uuidString: entry.id) ?? UUID(),
                filePath: URL(fileURLWithPath: entry.filePath),
                fileName: entry.fileName,
                language: entry.language,
                chunkCount: entry.chunkCount,
                fileSize: entry.fileSize
            )
        }
    }
}
