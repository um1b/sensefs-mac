//
//  RAGService.swift
//  Retrieval-Augmented Generation service
//
//  Note: Uses Apple Foundation Models when available (macOS 26+)
//  Falls back to search-only mode on earlier macOS versions
//

import Foundation

/// Service for RAG (Retrieval-Augmented Generation) chat functionality
actor RAGService {
    static let shared = RAGService()

    private let indexingService = IndexingService.shared
    private var isAvailable = false

    private init() {
        Task {
            await checkAvailability()
        }
    }

    // MARK: - Availability Check

    private func checkAvailability() async {
        // Apple Foundation Models requires macOS 26.0 or newer
        if #available(macOS 26.0, *) {
            // Will be available in future macOS releases
            print("✅ Apple Foundation Models available")
            isAvailable = true
        } else {
            print("ℹ️ Apple Foundation Models requires macOS 26 or newer")
            print("ℹ️ Running in search-only mode")
            isAvailable = false
        }
    }

    func getAvailability() -> Bool {
        return isAvailable
    }

    // MARK: - RAG Pipeline

    /// Generate a response using RAG (Retrieval-Augmented Generation)
    func generateResponse(for userMessage: String) async -> (response: String, context: [SearchResult]) {
        // Use agentic RAG for intelligent multi-step search and synthesis
        let agenticService = AgenticRAGService.shared
        return await agenticService.generateResponse(for: userMessage)
    }

    /// Generate streaming response for real-time updates
    func generateStreamingResponse(
        for userMessage: String,
        onToken: @escaping @Sendable (String) -> Void
    ) async -> [SearchResult] {
        // Use agentic RAG for intelligent streaming response
        let agenticService = AgenticRAGService.shared
        return await agenticService.generateStreamingResponse(for: userMessage, onToken: onToken)
    }

    // MARK: - Helper Methods

    private func buildContext(from results: [SearchResult]) -> String {
        guard !results.isEmpty else {
            return "No relevant documents found in the knowledge base."
        }

        var context = "# Relevant Documents from Knowledge Base\n\n"

        for (index, result) in results.enumerated() {
            context += """
            ## Document \(index + 1): \(result.fileName)
            Path: \(result.filePath.path)
            Relevance Score: \(String(format: "%.1f%%", result.score * 100))

            Content:
            \(result.content)

            ---

            """
        }

        return context
    }

    private func fallbackResponse(userMessage: String, context: String, results: [SearchResult]) -> String {
        if results.isEmpty {
            return """
            I searched your knowledge base but didn't find any relevant documents for: "\(userMessage)"

            **Suggestions:**
            • Try indexing more documents in the Index tab
            • Rephrase your question with different keywords
            • Check if the topic is covered in your indexed files

            **Note:** This app uses semantic search to find relevant documents. AI-powered chat responses require macOS 26 or newer with Apple Intelligence support.
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
            response += "\n\n*Note: AI-powered responses require macOS 26+ with Apple Intelligence. Currently showing search results only.*"

            return response
        }
    }

    /// Reset the conversation session
    func resetSession() async {
        let agenticService = AgenticRAGService.shared
        await agenticService.resetSession()
        print("🔄 Chat session reset")
    }
}
