//
//  SpellChecker.swift
//  Spell correction service for search queries
//

import Foundation
import AppKit

class SpellChecker {
    private let checker = NSSpellChecker.shared

    /// Get the system's preferred language for spell checking
    private var systemLanguage: String {
        // Get the user's preferred language
        if let preferredLanguage = Locale.current.language.languageCode?.identifier {
            return preferredLanguage
        }
        return "en" // Fallback to English
    }

    /// Convert detected language code to NSSpellChecker format
    private func convertLanguageCode(_ detectedLang: String) -> String {
        // Map common language codes to NSSpellChecker format
        switch detectedLang {
        case "zh-Hans": return "zh-Hans"
        case "zh-Hant": return "zh-Hant"
        default: return detectedLang
        }
    }

    /// Correct spelling in a query string using detected language or system default
    func correctSpelling(_ text: String, language: String? = nil) -> String {
        guard !text.isEmpty else { return text }

        // Use provided language, fallback to system language
        let spellCheckLanguage = language ?? systemLanguage
        let convertedLanguage = convertLanguageCode(spellCheckLanguage)

        // Set the language for spell checking
        checker.setLanguage(convertedLanguage)

        var correctedText = text
        let range = NSRange(location: 0, length: (text as NSString).length)

        // Find all misspelled words
        var misspelledRanges: [NSRange] = []
        var currentRange = range

        while currentRange.length > 0 {
            let misspelledRange = checker.checkSpelling(
                of: correctedText,
                startingAt: currentRange.location,
                language: convertedLanguage,
                wrap: false,
                inSpellDocumentWithTag: 0,
                wordCount: nil
            )

            if misspelledRange.location == NSNotFound {
                break
            }

            misspelledRanges.append(misspelledRange)
            currentRange = NSRange(
                location: misspelledRange.location + misspelledRange.length,
                length: range.length - (misspelledRange.location + misspelledRange.length)
            )
        }

        // Correct each misspelled word (process in reverse to maintain indices)
        var corrections: [(range: NSRange, word: String, suggestion: String)] = []

        for misspelledRange in misspelledRanges.reversed() {
            let misspelledWord = (correctedText as NSString).substring(with: misspelledRange)

            // Get suggestions for the misspelled word
            let guesses = checker.guesses(
                forWordRange: misspelledRange,
                in: correctedText,
                language: convertedLanguage,
                inSpellDocumentWithTag: 0
            )

            if let bestGuess = guesses?.first {
                corrections.append((misspelledRange, misspelledWord, bestGuess))
                correctedText = (correctedText as NSString).replacingCharacters(
                    in: misspelledRange,
                    with: bestGuess
                )
            }
        }

        // Log corrections
        if !corrections.isEmpty {
            for correction in corrections.reversed() {
                print("📝 Spell correction: '\(correction.word)' → '\(correction.suggestion)'")
            }
        }

        return correctedText
    }

    /// Check if a word is spelled correctly
    func isCorrect(_ word: String, language: String? = nil) -> Bool {
        let spellCheckLanguage = language ?? systemLanguage
        let convertedLanguage = convertLanguageCode(spellCheckLanguage)

        checker.setLanguage(convertedLanguage)
        let misspelledRange = checker.checkSpelling(
            of: word,
            startingAt: 0,
            language: convertedLanguage,
            wrap: false,
            inSpellDocumentWithTag: 0,
            wordCount: nil
        )
        return misspelledRange.location == NSNotFound
    }
}
