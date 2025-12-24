//
//  AgenticRAGService.swift
//  Agentic Retrieval-Augmented Generation service
//
//  This service implements an intelligent RAG pipeline where the AI:
//  1. Analyzes the user's question to create optimized search queries
//  2. Executes multiple refined searches iteratively
//  3. Evaluates search quality and decides whether to search again
//  4. Synthesizes a coherent answer from retrieved context
//

import Foundation

/// Tool definition for vector search operations
struct SearchTool: Codable {
    let type = "function"
    let function: FunctionDefinition

    struct FunctionDefinition: Codable {
        let name = "vector_search"
        let description = "Search the knowledge base using semantic similarity. Returns the most relevant documents matching the query."
        let parameters: Parameters

        struct Parameters: Codable {
            let type = "object"
            let properties: [String: Property]
            let required: [String]

            struct Property: Codable {
                let type: String
                let description: String
                let items: Items?

                struct Items: Codable {
                    let type: String
                }
            }
        }
    }
}

/// Response from the AI including tool calls
struct AgentResponse {
    let content: String?
    let toolCalls: [ToolCall]?
    let finishReason: String

    struct ToolCall {
        let id: String
        let name: String
        let arguments: SearchArguments

        struct SearchArguments: Codable {
            let queries: [String]
            let limit: Int?
            let reasoning: String?
        }
    }
}

/// Conversation turn tracking
private struct ConversationTurn {
    let userMessage: String
    let retrievedDocs: [SearchResult]
    let response: String
    let timestamp: Date
}

/// Agentic RAG service that uses AI to orchestrate searches
actor AgenticRAGService {
    static let shared = AgenticRAGService()

    private let indexingService = IndexingService.shared
    private var conversationHistory: [[String: String]] = []
    private var conversationTurns: [ConversationTurn] = []
    private let maxIterations = 3  // Prevent infinite loops
    private let maxHistoryTurns = 5  // Keep last 5 conversation turns

    private init() {}

    // MARK: - Main RAG Pipeline

    /// Generate response using agentic RAG approach
    func generateResponse(for userMessage: String) async -> (response: String, context: [SearchResult]) {
        // Reset conversation for new query
        conversationHistory = []

        // Check for follow-up questions and expand context
        let isFollowUp = detectFollowUpQuestion(userMessage)
        var expandedQuery = userMessage

        if isFollowUp && !conversationTurns.isEmpty {
            let lastTurn = conversationTurns.last!
            expandedQuery = "\(lastTurn.userMessage) \(userMessage)"
            print("🔗 Follow-up detected. Expanded query: \(expandedQuery)")
        }

        // Start the agentic loop
        var allResults: [SearchResult] = []
        var currentIteration = 0
        var isComplete = false
        var finalResponse = ""

        // Add initial user message
        addMessage(role: "user", content: expandedQuery)

        while !isComplete && currentIteration < maxIterations {
            currentIteration += 1

            // Get AI decision on what to do next
            let agentDecision = await planNextAction(userMessage: userMessage, iteration: currentIteration, previousResults: allResults)

            switch agentDecision {
            case .search(let queries, let reasoning):
                print("🔍 Iteration \(currentIteration): Searching for: \(queries)")
                if let reasoning = reasoning {
                    print("💭 Reasoning: \(reasoning)")
                }

                // Execute searches
                let newResults = await executeSearches(queries: queries)
                allResults.append(contentsOf: newResults)

                // Add search results to conversation
                let resultsContext = formatSearchResults(newResults)
                addMessage(role: "function", content: "Search results:\n\(resultsContext)")

            case .synthesize(let response):
                print("✅ Synthesizing final answer")
                finalResponse = response
                isComplete = true

            case .needsMoreInfo(let questions):
                print("❓ AI needs more information: \(questions)")
                finalResponse = generateClarificationResponse(questions: questions, results: allResults)
                isComplete = true
            }
        }

        // If we hit max iterations, synthesize what we have
        if !isComplete {
            finalResponse = await synthesizeFinalAnswer(userMessage: userMessage, results: allResults)
        }

        // Deduplicate results by file path
        let uniqueResults = deduplicateResults(allResults)

        // Save conversation turn for context in future queries
        let turn = ConversationTurn(
            userMessage: userMessage,
            retrievedDocs: uniqueResults,
            response: finalResponse,
            timestamp: Date()
        )
        conversationTurns.append(turn)

        // Keep only recent turns
        if conversationTurns.count > maxHistoryTurns {
            conversationTurns.removeFirst()
        }

        return (finalResponse, uniqueResults)
    }

    /// Generate streaming response with real-time updates
    func generateStreamingResponse(
        for userMessage: String,
        onToken: @escaping @Sendable (String) -> Void
    ) async -> [SearchResult] {
        // For now, send chunks of the non-streaming response
        let (response, context) = await generateResponse(for: userMessage)

        // Stream the response in chunks
        let words = response.split(separator: " ")
        for (index, word) in words.enumerated() {
            let chunk = String(word) + (index < words.count - 1 ? " " : "")
            onToken(chunk)

            // Add small delay for better streaming effect
            try? await Task.sleep(nanoseconds: 20_000_000) // 20ms
        }

        return context
    }

    // MARK: - Agent Decision Making

    private enum AgentAction {
        case search(queries: [String], reasoning: String?)
        case synthesize(response: String)
        case needsMoreInfo(questions: [String])
    }

    private func planNextAction(userMessage: String, iteration: Int, previousResults: [SearchResult]) async -> AgentAction {
        // For now, implement a rule-based approach
        // In the future, this could use an LLM with tool calling

        if iteration == 1 {
            // First iteration: generate search queries
            let queries = generateSearchQueries(from: userMessage)
            return .search(
                queries: queries,
                reasoning: "Initial search to find relevant context for the user's question"
            )
        } else if iteration == 2 {
            // Second iteration: refine search based on what we found
            let refinedQueries = generateRefinedQueries(from: userMessage, previousResults: previousResults)
            return .search(
                queries: refinedQueries,
                reasoning: "Refining search with more specific queries to fill knowledge gaps"
            )
        } else {
            // Final iteration: synthesize answer
            return .synthesize(response: "Synthesizing from available context...")
        }
    }

    // MARK: - Query Generation

    private func generateSearchQueries(from userMessage: String) -> [String] {
        // Intelligent query expansion:
        // 1. Clean and extract core intent
        // 2. Extract key concepts
        // 3. Generate related queries

        // First, clean the query to remove conversational filler
        let cleanedQuery = cleanQuery(userMessage)

        var queries: [String] = []

        // Only add cleaned query if it's different and meaningful
        if !cleanedQuery.isEmpty && cleanedQuery != userMessage {
            queries.append(cleanedQuery)
        }

        // Also include original if not too verbose
        if userMessage.split(separator: " ").count <= 15 {
            queries.append(userMessage)
        }

        // Extract keywords and create focused queries
        let keywords = extractKeywords(from: cleanedQuery.isEmpty ? userMessage : cleanedQuery)

        // Add individual keyword queries
        for keyword in keywords.prefix(2) {
            queries.append(keyword)
        }

        // Create combination queries
        if keywords.count >= 2 {
            queries.append(keywords.prefix(2).joined(separator: " "))
        }

        // Handle question patterns
        if userMessage.lowercased().contains("how") {
            queries.append("how to \(keywords.joined(separator: " "))")
            queries.append("guide \(keywords.joined(separator: " "))")
        } else if userMessage.lowercased().contains("what") {
            queries.append("definition \(keywords.joined(separator: " "))")
            queries.append("explanation \(keywords.joined(separator: " "))")
        } else if userMessage.lowercased().contains("why") {
            queries.append("reason \(keywords.joined(separator: " "))")
            queries.append("cause \(keywords.joined(separator: " "))")
        }

        return Array(Set(queries)).prefix(5).map { String($0) }
    }

    private func generateRefinedQueries(from userMessage: String, previousResults: [SearchResult] = []) -> [String] {
        // Second-pass queries with gap analysis
        let cleanedQuery = cleanQuery(userMessage)
        let keywords = extractKeywords(from: cleanedQuery.isEmpty ? userMessage : cleanedQuery)

        var queries: [String] = []

        // Analyze previous results to find gaps
        if !previousResults.isEmpty {
            let foundTopics = Set(previousResults.flatMap { extractKeywords(from: $0.content) })
            let missingKeywords = Set(keywords).subtracting(foundTopics)

            // Target missing information
            for keyword in missingKeywords.prefix(2) {
                queries.append("detailed \(keyword)")
                queries.append("\(keyword) tutorial")
            }
        }

        // Try more specific combinations
        for keyword in keywords.prefix(2) {
            queries.append("example \(keyword)")
            queries.append("\(keyword) documentation")
            queries.append("\(keyword) implementation")
        }

        // Add code-specific queries if applicable
        if userMessage.lowercased().contains("code") ||
           userMessage.lowercased().contains("implement") ||
           userMessage.lowercased().contains("function") {
            queries.append("code example \(keywords.prefix(2).joined(separator: " "))")
            queries.append("implementation guide \(keywords.prefix(2).joined(separator: " "))")
        }

        // Add conceptual queries for "what/why" questions
        if userMessage.lowercased().contains("what") || userMessage.lowercased().contains("why") {
            queries.append("concept \(keywords.prefix(2).joined(separator: " "))")
            queries.append("explanation \(keywords.prefix(2).joined(separator: " "))")
        }

        return Array(Set(queries)).prefix(5).map { String($0) }
    }

    private func cleanQuery(_ query: String) -> String {
        // Remove conversational filler and extract core intent
        var cleaned = query
        let original = query

        // Common conversational phrases to remove
        let fillerPhrases = [
            "I'm sorry, but I'm unable to find any information on",
            "I'm sorry, but I'm unable to find information on",
            "I cannot find any information about",
            "I don't have information about",
            "Could you provide more details or clarify what",
            "Could you provide more details about",
            "Could you clarify what",
            "Can you tell me about",
            "Can you explain",
            "Please tell me about",
            "Please explain",
            "I would like to know about",
            "I want to know about",
            "Tell me about",
            "Explain to me",
            "What is",
            "What are",
            "Who is",
            "Who are",
            "Where is",
            "When is",
            "How do I",
            "How can I",
            "Why does",
            "Why do"
        ]

        // Remove filler phrases (case-insensitive)
        for phrase in fillerPhrases {
            let pattern = phrase.lowercased()
            if cleaned.lowercased().hasPrefix(pattern) {
                cleaned = String(cleaned.dropFirst(pattern.count)).trimmingCharacters(in: .whitespaces)
            }
        }

        // Remove trailing question marks and punctuation
        cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "?.!,"))

        // Remove "refers to" pattern
        if let referToRange = cleaned.range(of: " refers to", options: .caseInsensitive) {
            cleaned = String(cleaned[..<referToRange.lowerBound])
        }

        // Remove quotes around the search term
        cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))

        // Collapse multiple spaces
        cleaned = cleaned.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        cleaned = cleaned.trimmingCharacters(in: .whitespaces)

        // Log query cleaning if significant changes were made
        if cleaned != original && !cleaned.isEmpty {
            print("🧹 Query cleaned: \"\(original)\" → \"\(cleaned)\"")
        }

        return cleaned
    }

    private func extractKeywords(from text: String) -> [String] {
        // Simple keyword extraction
        let stopWords = Set([
            "the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for",
            "of", "with", "by", "from", "is", "are", "was", "were", "be", "been",
            "have", "has", "had", "do", "does", "did", "will", "would", "could",
            "should", "may", "might", "can", "what", "how", "why", "when", "where",
            "who", "which", "this", "that", "these", "those", "i", "you", "me",
            "my", "your", "about", "tell", "explain", "describe", "refers"
        ])

        let words = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && !stopWords.contains($0) && $0.count > 2 }

        return Array(Set(words))
    }

    // MARK: - Search Execution

    private func executeSearches(queries: [String]) async -> [SearchResult] {
        var allResults: [SearchResult] = []

        for query in queries {
            let (results, _) = await indexingService.search(query: query, limit: 3)
            allResults.append(contentsOf: results)
        }

        // Re-rank results for better relevance
        let rerankedResults = rerankResults(allResults, query: queries.first ?? "")

        // Sort by score and take top results
        return Array(rerankedResults.sorted { $0.score > $1.score }.prefix(10))
    }

    /// Re-rank search results using additional signals beyond cosine similarity
    private func rerankResults(_ results: [SearchResult], query: String) -> [SearchResult] {
        let queryTerms = Set(extractKeywords(from: query))

        return results.map { result in
            var boostedScore = result.score
            let contentTerms = Set(extractKeywords(from: result.content))

            // 1. Term coverage boost (30%)
            let termOverlap = queryTerms.intersection(contentTerms).count
            if !queryTerms.isEmpty {
                let termCoverage = Float(termOverlap) / Float(queryTerms.count)
                boostedScore *= (1.0 + termCoverage * 0.3)
            }

            // 2. Exact phrase match boost (20%)
            if result.content.lowercased().contains(query.lowercased()) {
                boostedScore *= 1.2
            }

            // 3. Title/filename relevance boost (15%)
            let fileNameTerms = Set(extractKeywords(from: result.fileName))
            let fileNameOverlap = queryTerms.intersection(fileNameTerms).count
            if fileNameOverlap > 0 {
                boostedScore *= 1.15
            }

            // 4. Content quality signals
            // Penalty for very short content (likely incomplete)
            if result.content.count < 100 {
                boostedScore *= 0.8
            }

            // Boost for medium-length, informative content
            if result.content.count >= 200 && result.content.count <= 1000 {
                boostedScore *= 1.1
            }

            // 5. Language match (slight boost for English content)
            if result.language == "en" && query.range(of: "[a-zA-Z]", options: .regularExpression) != nil {
                boostedScore *= 1.05
            }

            // 6. Code detection boost for technical queries
            if (query.lowercased().contains("code") ||
                query.lowercased().contains("function") ||
                query.lowercased().contains("implement")) &&
               (result.content.contains("{") || result.content.contains("def ") || result.content.contains("func ")) {
                boostedScore *= 1.15
            }

            // Cap at 1.0 to maintain score range
            return SearchResult(
                id: result.id,
                filePath: result.filePath,
                fileName: result.fileName,
                content: result.content,
                chunkIndex: result.chunkIndex,
                language: result.language,
                score: min(boostedScore, 1.0),
                avgScore: result.avgScore,
                maxScore: result.maxScore,
                totalChunks: result.totalChunks
            )
        }
    }

    // MARK: - Response Synthesis

    private func synthesizeFinalAnswer(userMessage: String, results: [SearchResult]) async -> String {
        if results.isEmpty {
            return """
            I searched your knowledge base but couldn't find relevant information for: "\(userMessage)"

            **Suggestions:**
            • Try rephrasing your question with different keywords
            • Index more documents that might contain this information
            • Check if the topic is covered in your files

            **Search Attempts:**
            I tried multiple search strategies but didn't find matching content.
            """
        }

        // Group results by relevance
        let highRelevance = results.filter { $0.score >= 0.7 }
        let mediumRelevance = results.filter { $0.score >= 0.5 && $0.score < 0.7 }

        var response = "**Answer to:** \"\(userMessage)\"\n\n"

        // Synthesize based on relevance
        if !highRelevance.isEmpty {
            response += "**Key Findings:**\n\n"
            for (index, result) in highRelevance.prefix(3).enumerated() {
                response += """
                **\(index + 1). From \(result.fileName):**
                \(result.content.prefix(400))\(result.content.count > 400 ? "..." : "")

                *Match: \(String(format: "%.0f%%", result.score * 100))* • [View: `\(result.filePath.lastPathComponent)`]

                """
            }
        }

        if !mediumRelevance.isEmpty {
            response += "\n**Additional Context:**\n\n"
            for result in mediumRelevance.prefix(2) {
                response += "• **\(result.fileName)**: \(result.content.prefix(200))...\n"
            }
        }

        response += "\n---\n"
        response += "**💡 Sources:** Found \(results.count) relevant document(s) • Click source count to see all"

        return response
    }

    private func generateClarificationResponse(questions: [String], results: [SearchResult]) -> String {
        var response = "I found some information, but I need clarification:\n\n"

        for (index, question) in questions.enumerated() {
            response += "\(index + 1). \(question)\n"
        }

        if !results.isEmpty {
            response += "\n**What I found so far:**\n"
            for result in results.prefix(2) {
                response += "• \(result.fileName): \(result.content.prefix(100))...\n"
            }
        }

        return response
    }

    // MARK: - Helper Methods

    private func formatSearchResults(_ results: [SearchResult]) -> String {
        guard !results.isEmpty else {
            return "No results found."
        }

        var formatted = ""
        for (index, result) in results.enumerated() {
            formatted += """
            [\(index + 1)] \(result.fileName) (score: \(String(format: "%.2f", result.score)))
            \(result.content.prefix(300))
            ---

            """
        }
        return formatted
    }

    private func deduplicateResults(_ results: [SearchResult]) -> [SearchResult] {
        var seen = Set<String>()
        var unique: [SearchResult] = []

        for result in results {
            let key = result.filePath.path
            if !seen.contains(key) {
                seen.insert(key)
                unique.append(result)
            }
        }

        return unique.sorted { $0.score > $1.score }
    }

    private func addMessage(role: String, content: String) {
        conversationHistory.append(["role": role, "content": content])
    }

    /// Detect if a message is a follow-up question
    private func detectFollowUpQuestion(_ message: String) -> Bool {
        let followUpIndicators = [
            "what about", "how about", "tell me more", "elaborate",
            "what else", "can you explain", "why is that", "and that",
            "also", "additionally", "furthermore", "more details",
            "expand on", "continue", "go on", "keep going",
            "more info", "tell me about that", "explain that"
        ]

        let lowercased = message.lowercased()

        // Check for follow-up indicators
        for indicator in followUpIndicators {
            if lowercased.contains(indicator) {
                return true
            }
        }

        // Check for short queries (likely follow-ups)
        let wordCount = message.split(separator: " ").count
        if wordCount <= 3 && !conversationTurns.isEmpty {
            return true
        }

        // Check for pronouns without clear antecedents (it, that, this, those)
        let pronouns = ["it", "that", "this", "those", "these"]
        let words = lowercased.split(separator: " ").map { String($0) }
        if words.count <= 8 && pronouns.contains(where: { words.contains($0) }) {
            return true
        }

        return false
    }

    /// Reset the conversation session
    func resetSession() async {
        conversationHistory.removeAll()
        conversationTurns.removeAll()
        print("🔄 Agentic chat session reset")
    }
}
