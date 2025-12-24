//
//  LanguageModel.swift
//  Language model for embedding support
//

import Foundation
import NaturalLanguage

struct LanguageModel: Identifiable, Hashable {
    let id: String
    let name: String
    let flag: String
    let nlLanguage: NLLanguage
    var isDownloaded: Bool
    var isDownloading: Bool = false

    static let supportedLanguages: [LanguageModel] = [
        LanguageModel(id: "en", name: "English", flag: "🇬🇧", nlLanguage: .english, isDownloaded: true),
        LanguageModel(id: "ja", name: "Japanese", flag: "🇯🇵", nlLanguage: .japanese, isDownloaded: false),
        LanguageModel(id: "zh-Hans", name: "Chinese (Simplified)", flag: "🇨🇳", nlLanguage: .simplifiedChinese, isDownloaded: false),
        LanguageModel(id: "zh-Hant", name: "Chinese (Traditional)", flag: "🇹🇼", nlLanguage: .traditionalChinese, isDownloaded: false),
        LanguageModel(id: "es", name: "Spanish", flag: "🇪🇸", nlLanguage: .spanish, isDownloaded: false),
        LanguageModel(id: "fr", name: "French", flag: "🇫🇷", nlLanguage: .french, isDownloaded: false),
        LanguageModel(id: "de", name: "German", flag: "🇩🇪", nlLanguage: .german, isDownloaded: false),
        LanguageModel(id: "ko", name: "Korean", flag: "🇰🇷", nlLanguage: .korean, isDownloaded: false),
        LanguageModel(id: "it", name: "Italian", flag: "🇮🇹", nlLanguage: .italian, isDownloaded: false),
        LanguageModel(id: "pt", name: "Portuguese", flag: "🇵🇹", nlLanguage: .portuguese, isDownloaded: false),
        LanguageModel(id: "ru", name: "Russian", flag: "🇷🇺", nlLanguage: .russian, isDownloaded: false),
        LanguageModel(id: "nl", name: "Dutch", flag: "🇳🇱", nlLanguage: .dutch, isDownloaded: false),
    ]
}
