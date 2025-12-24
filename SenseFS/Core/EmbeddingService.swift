//
//  EmbeddingService.swift
//  NLContextualEmbedding service with multi-language support
//

import Foundation
import NaturalLanguage

actor EmbeddingService {
    static let shared = EmbeddingService()

    private var contextualEmbeddings: [NLLanguage: NLContextualEmbedding] = [:]
    private let recognizer = NLLanguageRecognizer()

    // Preferred language for ambiguous short queries (default to Japanese for CJK text)
    var preferredLanguageForCJK: NLLanguage = .japanese

    private init() {
        // Try to load English contextual embedding
        if let embedding = NLContextualEmbedding(language: .english) {
            contextualEmbeddings[.english] = embedding
            if embedding.hasAvailableAssets {
                try? embedding.load()
                print("✅ Loaded contextual embedding for: en")
            } else {
                print("⚠️ English contextual embedding exists but assets not available")
            }
        }
        print("ℹ️ Using NLContextualEmbedding for better semantic search")
        print("ℹ️ Check Settings tab to see all available languages on your system.")
    }

    /// Check which languages have contextual embeddings available on this system
    func checkAvailableLanguages(_ languages: [NLLanguage]) -> [(language: NLLanguage, hasAssets: Bool)] {
        var results: [(language: NLLanguage, hasAssets: Bool)] = []

        for language in languages {
            print("🔍 Checking NLContextualEmbedding for \(language.rawValue)...")

            if let embedding = NLContextualEmbedding(language: language) {
                let hasAssets = embedding.hasAvailableAssets

                if hasAssets {
                    // Try to load it
                    do {
                        try embedding.load()
                        contextualEmbeddings[language] = embedding
                        print("✅ Loaded contextual embedding for: \(language.rawValue)")
                        print("   - Dimension: \(embedding.dimension)")
                        print("   - Max sequence length: \(embedding.maximumSequenceLength)")
                        print("   - Revision: \(embedding.revision)")
                        results.append((language, true))
                    } catch {
                        print("⚠️ Failed to load \(language.rawValue): \(error)")
                        results.append((language, false))
                    }
                } else {
                    print("⚠️ \(language.rawValue) contextual embedding exists but assets not downloaded")
                    results.append((language, false))
                }
            } else {
                print("❌ No contextual embedding available for: \(language.rawValue)")
                results.append((language, false))
            }
        }

        return results
    }

    /// Get list of loaded languages
    func getLoadedLanguages() -> [NLLanguage] {
        return Array(contextualEmbeddings.keys)
    }

    /// Load a language embedding if it's available but not yet loaded
    func ensureLanguageLoaded(_ language: NLLanguage) async -> Bool {
        // Already loaded
        if contextualEmbeddings[language] != nil {
            print("ℹ️ \(language.rawValue) already loaded")
            return true
        }

        // Try to load it
        guard let embedding = NLContextualEmbedding(language: language) else {
            print("❌ No contextual embedding available for \(language.rawValue)")
            return false
        }

        guard embedding.hasAvailableAssets else {
            print("⚠️ Assets not available for \(language.rawValue)")
            return false
        }

        do {
            try embedding.load()
            contextualEmbeddings[language] = embedding
            print("✅ Auto-loaded contextual embedding for: \(language.rawValue)")
            print("   💾 Current memory: \(contextualEmbeddings.count) languages loaded")
            return true
        } catch {
            print("⚠️ Failed to auto-load \(language.rawValue): \(error)")
            return false
        }
    }

    /// Unload a language embedding to free memory
    func unloadLanguage(_ language: NLLanguage) {
        if let embedding = contextualEmbeddings[language] {
            embedding.unload()
            contextualEmbeddings.removeValue(forKey: language)
            print("🗑️ Unloaded contextual embedding for: \(language.rawValue)")
            print("   💾 Current memory: \(contextualEmbeddings.count) languages loaded")
        }
    }

    /// Unload all languages except the specified ones
    func unloadAllExcept(_ keepLanguages: Set<NLLanguage>) {
        let toUnload = contextualEmbeddings.keys.filter { !keepLanguages.contains($0) }

        if !toUnload.isEmpty {
            print("🧹 Unloading unused languages: \(toUnload.map { $0.rawValue }.joined(separator: ", "))")
            for language in toUnload {
                unloadLanguage(language)
            }
        }
    }

    /// Detect language from text (use full document for better accuracy)
    func detectLanguage(_ text: String) -> String? {
        guard !text.isEmpty else { return nil }

        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }

        // Use more text for better detection (up to 2000 chars for better accuracy)
        let sampleText = String(cleaned.prefix(2000))
        let isShortQuery = cleaned.count < 20 // Short queries are harder to detect

        recognizer.reset()
        recognizer.processString(sampleText)

        // Get language hypotheses with confidence scores
        let hypotheses = recognizer.languageHypotheses(withMaximum: 3)

        guard let detectedLanguage = recognizer.dominantLanguage else {
            return "en" // Default to English if detection fails
        }

        // Special handling for Japanese vs Chinese confusion
        // Japanese text often contains hiragana/katakana which distinguishes it from Chinese
        if detectedLanguage == .simplifiedChinese || detectedLanguage == .traditionalChinese {
            // Check for hiragana (ぁ-ん) or katakana (ァ-ヶ)
            let hiraganaRange = "\u{3040}"..."\u{309F}"
            let katakanaRange = "\u{30A0}"..."\u{30FF}"

            let hasHiragana = sampleText.unicodeScalars.contains { scalar in
                hiraganaRange.contains(String(scalar))
            }
            let hasKatakana = sampleText.unicodeScalars.contains { scalar in
                katakanaRange.contains(String(scalar))
            }

            if hasHiragana || hasKatakana {
                print("🔍 Corrected Chinese → Japanese (found hiragana/katakana)")
                return NLLanguage.japanese.rawValue
            }

            // Check if Japanese is in the hypotheses with decent confidence
            if let jaScore = hypotheses[.japanese], jaScore > 0.3 {
                print("🔍 Corrected Chinese → Japanese (hypothesis score: \(jaScore))")
                return NLLanguage.japanese.rawValue
            }

            // For short queries with ambiguous CJK characters, use preferred language
            if isShortQuery {
                let confidence = hypotheses[detectedLanguage] ?? 0
                if confidence < 0.8 {
                    print("🔍 Short ambiguous CJK query → using preferred language: \(preferredLanguageForCJK.rawValue)")
                    return preferredLanguageForCJK.rawValue
                }
            }
        }

        print("🔍 Language detected: \(detectedLanguage.rawValue) (confidence: \(hypotheses[detectedLanguage] ?? 0))")
        return detectedLanguage.rawValue
    }

    /// Generate embedding with specified language using NLContextualEmbedding
    func embedWithLanguage(_ text: String, language: String) -> [Float]? {
        guard !text.isEmpty else { return nil }

        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }

        let nlLanguage = NLLanguage(language)

        // Get the embedding for the specified language (no fallback to avoid language mismatch)
        guard let embedding = contextualEmbeddings[nlLanguage] else {
            print("⚠️ No contextual embedding loaded for \(language). Available: \(contextualEmbeddings.keys.map { $0.rawValue })")
            return nil
        }

        // Generate contextual embedding with matching language
        do {
            let result = try embedding.embeddingResult(for: cleaned, language: nlLanguage)

            // Check sequence length
            guard result.sequenceLength > 0 else {
                print("⚠️ No vectors generated")
                return nil
            }

            // Collect all token vectors using enumeration
            var allVectors: [[Double]] = []
            let fullRange = cleaned.startIndex..<cleaned.endIndex

            result.enumerateTokenVectors(in: fullRange) { vector, _ in
                allVectors.append(vector)
                return true // Continue enumeration
            }

            guard !allVectors.isEmpty else {
                print("⚠️ No token vectors found")
                return nil
            }

            // For semantic search, we'll use mean pooling over all token vectors
            let dimension = allVectors[0].count
            var meanVector = [Float](repeating: 0, count: dimension)

            for vector in allVectors {
                for (index, value) in vector.enumerated() {
                    meanVector[index] += Float(value)
                }
            }

            let count = Float(allVectors.count)
            meanVector = meanVector.map { $0 / count }

            return meanVector
        } catch {
            print("⚠️ Failed to generate embedding: \(error)")
            return nil
        }
    }

    /// Generate embedding vector for text (auto-detects language)
    /// Returns tuple of (vector, language_code)
    func embed(_ text: String) -> (vector: [Float], language: String)? {
        guard !text.isEmpty else { return nil }

        // Clean text
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }

        // Detect language
        guard let detectedLanguage = detectLanguage(cleaned) else {
            return nil
        }

        // Generate embedding with detected language
        guard let vector = embedWithLanguage(cleaned, language: detectedLanguage) else {
            return nil
        }

        return (vector, detectedLanguage)
    }

    /// Calculate cosine similarity between two vectors
    func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0 }

        let dotProduct = zip(a, b).map(*).reduce(0, +)
        let magnitudeA = sqrt(a.map { $0 * $0 }.reduce(0, +))
        let magnitudeB = sqrt(b.map { $0 * $0 }.reduce(0, +))

        guard magnitudeA > 0, magnitudeB > 0 else { return 0 }

        return dotProduct / (magnitudeA * magnitudeB)
    }

    /// Request assets for a specific language
    func requestAssets(for language: NLLanguage) async throws -> Bool {
        print("📥 Requesting assets for \(language.rawValue)...")

        guard let embedding = NLContextualEmbedding(language: language) else {
            print("❌ No contextual embedding available for \(language.rawValue)")
            throw NSError(domain: "EmbeddingService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Language not supported"])
        }

        let result = try await embedding.requestAssets()

        switch result {
        case .available:
            print("✅ Assets available for \(language.rawValue)")
            // Try to load it
            try embedding.load()
            contextualEmbeddings[language] = embedding
            print("✅ Loaded contextual embedding for \(language.rawValue)")
            return true

        case .notAvailable:
            print("⚠️ Assets not available for \(language.rawValue)")
            return false

        case .error:
            print("❌ Error downloading assets for \(language.rawValue)")
            return false

        @unknown default:
            print("⚠️ Unknown result for \(language.rawValue)")
            return false
        }
    }
}
