//
//  RAGService.swift
//  Retrieval-Augmented Generation service using Apple Foundation Models
//

import Foundation
import FoundationModels

/// Service for RAG (Retrieval-Augmented Generation) chat functionality
actor RAGService {
    static let shared = RAGService()

    private let indexingService = IndexingService.shared
    private var sessionStorage: Any? // Stores LanguageModelSession when available
    private var isAvailable = false

    private init() {
        Task {
            await checkAvailability()
        }
    }

    // Helper to access session safely
    @available(macOS 26.0, *)
    private var session: LanguageModelSession? {
        get { sessionStorage as? LanguageModelSession }
        set { sessionStorage = newValue }
    }

    // MARK: - Availability Check

    private func checkAvailability() async {
        if #available(macOS 26.0, *) {
            let availability = SystemLanguageModel.default.availability

            switch availability {
            case .available:
                print("✅ Apple Foundation Models available")
                isAvailable = true
                await initializeSession()
            case .unavailable(let reason):
                print("⚠️ Apple Foundation Models unavailable: \(reason)")
                isAvailable = false
            }
        } else {
            print("ℹ️ Apple Foundation Models requires macOS 26 or newer")
            print("ℹ️ Running in search-only mode")
            isAvailable = false
        }
    }

    func getAvailability() -> Bool {
        return isAvailable
    }

    // MARK: - Session Management

    @available(macOS 26.0, *)
    private func initializeSession() async {
        // Initialize session with system instructions for RAG
        session = LanguageModelSession(
            instructions: """
            You are an intelligent AI assistant with semantic search access to the user's personal knowledge base.

            **CRITICAL ANTI-HALLUCINATION RULES:**
            1. ⚠️ **ONLY use information from the retrieved documents provided in the "# Context from Indexed Documents" section below**
            2. ⚠️ **NEVER use your general knowledge or training data to answer questions**
            3. ⚠️ **NEVER fabricate or invent file names - ONLY mention files that appear in the context below**
            4. ⚠️ **NEVER list documents as "not containing" information - if context is empty or irrelevant, just say "I don't have information about this"**
            5. ⚠️ **If no context is provided below, or all relevance scores are low, respond ONLY with: "I don't have information about this in your knowledge base."**
            6. ⚠️ **DO NOT create fake citations, references, or file names under any circumstances**

            **Your Role:**
            - Synthesize accurate answers ONLY from retrieved documents
            - Think critically about document relevance and completeness
            - Provide well-structured, markdown-formatted responses
            - Acknowledge knowledge gaps transparently

            **Response Guidelines:**

            1. **Document Analysis:**
               - Evaluate relevance scores (>70% = high confidence, 50-70% = moderate, <50% = not relevant)
               - Cross-reference multiple sources when available
               - Identify contradictions or gaps in the retrieved context
               - **If all scores are <50%, STOP and say you don't have this information**

            2. **Answer Structure:**
               - **FIRST**: Check if any documents have >50% relevance. If NO, respond with "I don't have information about [query] in your indexed documents."
               - Start with a direct answer ONLY if context is sufficient (>70% relevance)
               - Use **Key Findings** for high-confidence information (>70% relevance)
               - Use **Additional Context** for supporting details (50-70% relevance)
               - Add **Limitations** section if context is incomplete

            3. **Source Attribution:**
               - Always cite specific documents: "According to [filename]..."
               - Include relevance percentages for transparency
               - Quote directly when appropriate (use blockquotes)
               - Link to file paths for easy navigation
               - **NEVER cite documents that weren't provided in the context**

            4. **When Context is Insufficient:**
               - Respond with EXACTLY this template (no additions):

                 ```
                 I don't have information about "[user's question]" in your indexed documents.

                 **Suggestions:**
                 • Try rephrasing your question with different keywords
                 • Index more documents that might contain this information
                 • Check what's currently indexed in the Index tab
                 ```

               - DO NOT list file names that "don't contain" the information
               - DO NOT speculate or use general knowledge
               - DO NOT make up document names or references

            5. **Formatting Standards:**
               - Use markdown headers, lists, and code blocks
               - Keep paragraphs concise (2-4 sentences)
               - Use **bold** for key terms and *italics* for emphasis
               - Add horizontal rules (---) between major sections

            **Context Structure:**
            Each retrieved document includes:
            - `fileName`: Document name
            - `filePath`: Full file path (clickable reference)
            - `score`: Relevance percentage (0-100%)
            - `language`: Detected language
            - `content`: Text excerpt (chunked at 512 chars)

            **Quality Standards:**
            - Accuracy > Completeness (admit gaps rather than guess)
            - Ground all responses in retrieved documents ONLY
            - Be conversational yet precise (avoid jargon unless in source)
            - When uncertain, say "I'm not sure" rather than making assumptions
            """
        )
        print("✅ Foundation Models session initialized")
    }

    // MARK: - RAG Pipeline

    /// Generate a response using RAG (Retrieval-Augmented Generation)
    func generateResponse(for userMessage: String) async -> (response: String, context: [SearchResult]) {
        // Step 1: Use Agentic RAG for intelligent retrieval
        let agenticService = AgenticRAGService.shared

        // Execute agentic search (multi-iteration, query expansion, re-ranking)
        let (agenticResponse, agenticSearchResults) = await agenticService.generateResponse(for: userMessage)

        // Step 2: Check relevance quality before synthesis
        let hasRelevantResults = agenticSearchResults.contains { $0.score >= 0.5 }

        if !hasRelevantResults {
            print("⚠️ No relevant results found (all scores <50%). Returning no-results message.")
            let noResultsMessage = """
            I don't have information about **"\(userMessage)"** in your indexed documents.

            **Why this might happen:**
            - The topic isn't covered in your indexed files
            - Different terminology might be used in your documents
            - The documents haven't been indexed yet

            **Suggestions:**
            • Try rephrasing with different keywords
            • Index documents that contain information about this topic
            • Check the Index tab to see what's currently indexed

            **What I searched for:**
            I tried multiple search strategies but couldn't find matching content above the 50% relevance threshold.
            """
            return (noResultsMessage, [])
        }

        print("📊 Relevance check: \(agenticSearchResults.count) results, highest: \(String(format: "%.1f%%", (agenticSearchResults.first?.score ?? 0) * 100))")

        // Step 3: Build context from search results (retrieve full documents)
        let context = await buildContext(from: agenticSearchResults)

        // Step 4: Check if Foundation Models are available for synthesis
        guard isAvailable else {
            // Use agentic response as fallback
            print("ℹ️ Using agentic RAG response (Apple Intelligence unavailable)")
            return (agenticResponse, agenticSearchResults)
        }

        // Step 5: Build augmented prompt with retrieved context
        let augmentedPrompt = buildAugmentedPrompt(userMessage: userMessage, context: context)

        // Step 6: Generate response using Foundation Models
        if #available(macOS 26.0, *) {
            guard let session = session else {
                print("ℹ️ Using agentic RAG response (session unavailable)")
                return (agenticResponse, agenticSearchResults)
            }

            do {
                let response = try await session.respond(to: augmentedPrompt)
                print("✅ Using Apple Foundation Models for synthesis")
                return (response.content, agenticSearchResults)
            } catch {
                print("❌ Foundation Models generation failed: \(error)")
                print("ℹ️ Falling back to agentic RAG response")
                return (agenticResponse, agenticSearchResults)
            }
        } else {
            print("ℹ️ Using agentic RAG response (macOS 26+ required)")
            return (agenticResponse, agenticSearchResults)
        }
    }

    /// Generate streaming response for real-time updates
    func generateStreamingResponse(
        for userMessage: String,
        onToken: @escaping @Sendable (String) -> Void
    ) async -> [SearchResult] {
        // Step 1: Use Agentic RAG for intelligent retrieval
        let agenticService = AgenticRAGService.shared

        // Get search results first (non-streaming for context building)
        let (agenticResponse, agenticSearchResults) = await agenticService.generateResponse(for: userMessage)

        // Step 2: Check relevance quality before synthesis
        let hasRelevantResults = agenticSearchResults.contains { $0.score >= 0.5 }

        if !hasRelevantResults {
            print("⚠️ No relevant results found (all scores <50%). Returning no-results message.")
            let noResultsMessage = """
            I don't have information about **"\(userMessage)"** in your indexed documents.

            **Why this might happen:**
            - The topic isn't covered in your indexed files
            - Different terminology might be used in your documents
            - The documents haven't been indexed yet

            **Suggestions:**
            • Try rephrasing with different keywords
            • Index documents that contain information about this topic
            • Check the Index tab to see what's currently indexed

            **What I searched for:**
            I tried multiple search strategies but couldn't find matching content above the 50% relevance threshold.
            """

            // Stream the no-results message
            let words = noResultsMessage.split(separator: " ")
            for (index, word) in words.enumerated() {
                let chunk = String(word) + (index < words.count - 1 ? " " : "")
                onToken(chunk)
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
            return []
        }

        print("📊 Relevance check: \(agenticSearchResults.count) results, highest: \(String(format: "%.1f%%", (agenticSearchResults.first?.score ?? 0) * 100))")

        // Step 3: Build context from search results (retrieve full documents)
        let context = await buildContext(from: agenticSearchResults)

        // Step 4: Check if Foundation Models are available
        guard isAvailable else {
            print("⚠️ RAG: Foundation Models not available, using agentic fallback")
            // Stream the agentic response word by word
            let words = agenticResponse.split(separator: " ")
            for (index, word) in words.enumerated() {
                let chunk = String(word) + (index < words.count - 1 ? " " : "")
                onToken(chunk)
                try? await Task.sleep(nanoseconds: 20_000_000) // 20ms delay
            }
            return agenticSearchResults
        }

        print("✅ RAG: Foundation Models available, proceeding with AI generation")

        // Step 4: Build augmented prompt
        let augmentedPrompt = buildAugmentedPrompt(userMessage: userMessage, context: context)

        // Step 5: Stream response using Foundation Models
        if #available(macOS 26.0, *) {
            guard let session = session else {
                print("⚠️ RAG: Session is nil, using agentic fallback")
                let words = agenticResponse.split(separator: " ")
                for (index, word) in words.enumerated() {
                    let chunk = String(word) + (index < words.count - 1 ? " " : "")
                    onToken(chunk)
                    try? await Task.sleep(nanoseconds: 20_000_000)
                }
                return agenticSearchResults
            }

            print("🤖 RAG: Starting AI generation with prompt length: \(augmentedPrompt.count)")
            do {
                // Use streamResponse for real-time token generation
                let responseStream = session.streamResponse(to: augmentedPrompt)

                print("📡 RAG: Streaming response...")
                var previousContent = ""
                // Iterate over the stream and send each snapshot
                // Note: snapshots contain the full text so far, so we send only the delta
                for try await snapshot in responseStream {
                    let currentContent = snapshot.content
                    if currentContent.count > previousContent.count {
                        let delta = String(currentContent.dropFirst(previousContent.count))
                        onToken(delta)
                        previousContent = currentContent
                    }
                }
                print("✅ RAG: Streaming completed successfully")
            } catch {
                print("❌ RAG: Streaming generation failed: \(error)")
                print("ℹ️ Falling back to agentic RAG response")
                let words = agenticResponse.split(separator: " ")
                for (index, word) in words.enumerated() {
                    let chunk = String(word) + (index < words.count - 1 ? " " : "")
                    onToken(chunk)
                    try? await Task.sleep(nanoseconds: 20_000_000)
                }
            }
        } else {
            print("⚠️ RAG: macOS 26 not available, using agentic fallback")
            let words = agenticResponse.split(separator: " ")
            for (index, word) in words.enumerated() {
                let chunk = String(word) + (index < words.count - 1 ? " " : "")
                onToken(chunk)
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
        }

        return agenticSearchResults
    }

    // MARK: - Helper Methods

    /// Approximate token count (rough estimate: 1 token ≈ 3.5-4 characters for English)
    private func estimateTokenCount(_ text: String) -> Int {
        // More accurate estimation based on common tokenization patterns
        let words = text.split(separator: " ")
        var tokenCount = 0

        for word in words {
            // Most words are 1 token
            // Longer words (>8 chars) often split into 2-3 tokens
            let length = word.count
            if length <= 4 {
                tokenCount += 1
            } else if length <= 8 {
                tokenCount += 1
            } else {
                // Estimate: 1 token per ~4 characters for long words
                tokenCount += max(1, length / 4)
            }
        }

        // Add tokens for punctuation and special chars
        let specialChars = text.filter { ".,!?;:\n()[]{}\"'".contains($0) }.count
        tokenCount += specialChars / 2

        return tokenCount
    }

    private func buildContext(from results: [SearchResult]) async -> String {
        guard !results.isEmpty else {
            return "No relevant documents found in the knowledge base."
        }

        var context = "# Retrieved Documents from Knowledge Base\n\n"
        var validDocCount = 0
        var totalTokens = 0

        // Apple Foundation Models limit: 4096 tokens total
        // Reserve tokens for: system prompt (~800) + user query (~50-200) + response buffer (~1000)
        // Available for context: ~2000 tokens
        let maxContextTokens = 2_000
        let maxTokensPerDoc = 400 // Max tokens per document

        for (index, result) in results.enumerated() {
            // Log chunk info for debugging
            print("📄 Document \(index + 1): \(result.fileName) - Score: \(String(format: "%.1f%%", result.score * 100)), Chunk content: \(result.content.count) chars")

            // Retrieve full document content
            let fullContent = await indexingService.getFullDocument(filePath: result.filePath)

            guard let rawContent = fullContent, !rawContent.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty else {
                print("⚠️ Skipping document with empty or unavailable full content")
                continue
            }

            // Calculate tokens for the raw content
            let rawTokens = estimateTokenCount(rawContent)
            print("📊 Full document tokens: \(rawTokens)")

            // Smart truncation based on token limit
            var content = rawContent
            var contentTokens = rawTokens

            // If document exceeds per-doc limit, truncate around matched chunk
            if contentTokens > maxTokensPerDoc {
                // Estimate chars needed: tokens * 3.5 (average chars per token)
                let targetChars = Int(Double(maxTokensPerDoc) * 3.5)
                content = truncateDocument(rawContent, maxLength: targetChars, matchedChunk: result.content)
                contentTokens = estimateTokenCount(content)
                print("✂️ Truncated to \(contentTokens) tokens (from \(rawTokens))")
            }

            // Check if adding this document would exceed total token limit
            if totalTokens + contentTokens > maxContextTokens {
                print("⚠️ Context token limit reached (\(totalTokens) + \(contentTokens) > \(maxContextTokens)), stopping at \(validDocCount) documents")
                break
            }

            totalTokens += contentTokens
            print("✅ Using document: \(result.fileName) (\(contentTokens) tokens, total: \(totalTokens))")

            validDocCount += 1
            context += """
            ## Document \(validDocCount): \(result.fileName)
            - **Path:** `\(result.filePath.path)`
            - **Relevance Score:** \(String(format: "%.1f%%", result.score * 100))
            - **Language:** \(result.language)
            \(content.count < rawContent.count ? "- **Note:** Excerpt shown (most relevant \(content.count) of \(rawContent.count) chars)\n" : "")
            **Content:**
            ```
            \(content)
            ```

            ---

            """
        }

        if validDocCount == 0 {
            return "No relevant documents with content found in the knowledge base."
        }

        let finalTokenCount = estimateTokenCount(context)
        print("📊 Total context: \(validDocCount) documents, \(totalTokens) content tokens, \(finalTokenCount) total tokens (with formatting)")

        return context
    }

    /// Truncate document intelligently, keeping content around the matched chunk
    private func truncateDocument(_ fullContent: String, maxLength: Int, matchedChunk: String) -> String {
        guard fullContent.count > maxLength else {
            return fullContent
        }

        // Try to find the matched chunk in the full content
        if let matchRange = fullContent.range(of: matchedChunk, options: .caseInsensitive) {
            let matchStart = fullContent.distance(from: fullContent.startIndex, to: matchRange.lowerBound)

            // Extract context around the match
            let beforeChars = min(matchStart, maxLength / 3)
            let afterChars = min(fullContent.count - (matchStart + matchedChunk.count), maxLength / 3)

            let startIndex = fullContent.index(fullContent.startIndex, offsetBy: matchStart - beforeChars)
            let endIndex = fullContent.index(fullContent.startIndex, offsetBy: min(fullContent.count, matchStart + matchedChunk.count + afterChars))

            let excerpt = String(fullContent[startIndex..<endIndex])
            return "...\(excerpt)..."
        }

        // Fallback: take beginning of document
        let endIndex = fullContent.index(fullContent.startIndex, offsetBy: maxLength)
        return String(fullContent[..<endIndex]) + "..."
    }

    private func buildAugmentedPrompt(userMessage: String, context: String) -> String {
        return """
        # Context from Indexed Documents

        \(context)

        # User Question

        \(userMessage)

        # Instructions

        ⚠️ CRITICAL: Only use information from the "Context from Indexed Documents" section above.

        Based STRICTLY on the context provided above from the user's indexed documents:

        - If the context contains relevant information (relevance score ≥70%), use it to provide an accurate answer and cite the EXACT documents shown above
        - If relevance scores are 50-70%, acknowledge uncertainty: "Based on limited/tangential information..."
        - If the context is insufficient or empty, respond with: "I don't have information about this in your knowledge base."
        - DO NOT fabricate file names, quotes, or information not present in the context above
        - DO NOT list documents that "were searched" or "don't contain" information
        - Format your response in markdown for readability
        - Be conversational but precise
        """
    }

    private func fallbackResponse(userMessage: String, context: String, results: [SearchResult]) -> String {
        if results.isEmpty {
            return """
            I searched your knowledge base but didn't find any relevant documents for: "\(userMessage)"

            **Suggestions:**
            • Try indexing more documents in the Index tab
            • Rephrase your question with different keywords
            • Check if the topic is covered in your indexed files

            **Note:** This app uses semantic search to find relevant documents. AI-powered chat responses require Apple Intelligence to be available.
            """
        } else {
            // Format search results as a helpful response
            var response = "**Search Results for:** \"\(userMessage)\"\n\n"
            response += "I found **\(results.count) relevant document(s)** in your knowledge base:\n\n"

            for (index, result) in results.enumerated() {
                response += """
                **\(index + 1). \(result.fileName)** (Match: \(String(format: "%.1f%%", result.score * 100)))
                *Location:* `\(result.filePath.path)`

                **Preview:**
                \(result.content.prefix(300))\(result.content.count > 300 ? "..." : "")

                ---

                """
            }

            response += "\n**💡 Tip:** Click the source count button to view full document details."
            response += "\n\n*Note: Apple Intelligence is currently unavailable. Showing search results only.*"

            return response
        }
    }

    /// Reset the conversation session
    func resetSession() async {
        if #available(macOS 26.0, *) {
            await initializeSession()
            print("🔄 Chat session reset")
        }
    }
}
