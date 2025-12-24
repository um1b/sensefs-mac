//
//  SearchResult.swift
//  Search result model
//

import Foundation

struct SearchResult: Identifiable {
    let id: UUID
    let filePath: URL
    let fileName: String
    let content: String
    let chunkIndex: Int
    let language: String
    let score: Float
    let avgScore: Float
    let maxScore: Float
    let totalChunks: Int

    var formattedScore: String {
        String(format: "%.2f", score)
    }

    var displayFileName: String {
        fileName
    }

    var languageFlag: String {
        switch language {
        case "ja": return "🇯🇵"
        case "en": return "🇬🇧"
        case "es": return "🇪🇸"
        case "fr": return "🇫🇷"
        case "de": return "🇩🇪"
        case "zh-Hans": return "🇨🇳"
        case "zh-Hant": return "🇹🇼"
        case "ko": return "🇰🇷"
        case "it": return "🇮🇹"
        case "pt": return "🇵🇹"
        case "nl": return "🇳🇱"
        case "ru": return "🇷🇺"
        default: return "🌐"
        }
    }

    var scoreInfo: String {
        "avg: \(String(format: "%.3f", avgScore)) max: \(String(format: "%.3f", maxScore)) (\(totalChunks) chunks)"
    }
}
