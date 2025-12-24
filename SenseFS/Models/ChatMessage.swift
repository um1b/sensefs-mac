//
//  ChatMessage.swift
//  Chat message model for RAG conversations
//

import Foundation

struct ChatMessage: Identifiable {
    let id: UUID
    let content: String
    let isUser: Bool
    let timestamp: Date
    let retrievedContext: [SearchResult]?

    init(
        id: UUID = UUID(),
        content: String,
        isUser: Bool,
        timestamp: Date = Date(),
        retrievedContext: [SearchResult]? = nil
    ) {
        self.id = id
        self.content = content
        self.isUser = isUser
        self.timestamp = timestamp
        self.retrievedContext = retrievedContext
    }
}
