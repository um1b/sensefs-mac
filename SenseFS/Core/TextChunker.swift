//
//  TextChunker.swift
//  Text chunking utilities for better semantic search
//

import Foundation

struct TextChunk {
    let text: String
    let index: Int
}

actor TextChunker {
    /// Chunk text into smaller pieces for embedding
    /// Strategy: Sentence-based chunking with overlap (best for NLEmbedding)
    func chunkText(_ text: String, maxChunkSize: Int = 512, overlapSentences: Int = 1) -> [TextChunk] {
        return chunkBySentencesWithOverlap(text, maxChunkSize: maxChunkSize, overlapSentences: overlapSentences)
    }

    /// Chunk by sentences with overlap (prevents information loss at boundaries)
    private func chunkBySentencesWithOverlap(_ text: String, maxChunkSize: Int, overlapSentences: Int) -> [TextChunk] {
        let sentences = splitIntoSentences(text)
        guard !sentences.isEmpty else { return [TextChunk(text: text, index: 0)] }

        var chunks: [TextChunk] = []
        var chunkIndex = 0
        var sentenceIndex = 0

        while sentenceIndex < sentences.count {
            var currentChunk = ""
            var sentencesInChunk = 0
            var tempIndex = sentenceIndex

            // Build chunk with sentences
            while tempIndex < sentences.count {
                let sentence = sentences[tempIndex].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !sentence.isEmpty else {
                    tempIndex += 1
                    continue
                }

                let potentialChunk = currentChunk.isEmpty ? sentence : currentChunk + " " + sentence

                // Stop if adding this sentence exceeds limit
                if potentialChunk.count > maxChunkSize && !currentChunk.isEmpty {
                    break
                }

                // Handle very long single sentence
                if sentence.count > maxChunkSize {
                    if currentChunk.isEmpty {
                        // Split this sentence and make it a chunk
                        let subChunks = splitLongSentence(sentence, maxChunkSize: maxChunkSize)
                        for subChunk in subChunks {
                            chunks.append(TextChunk(text: subChunk, index: chunkIndex))
                            chunkIndex += 1
                        }
                        tempIndex += 1
                        sentenceIndex = tempIndex
                        sentencesInChunk = 0
                        currentChunk = ""
                        continue
                    } else {
                        break
                    }
                }

                currentChunk = potentialChunk
                sentencesInChunk += 1
                tempIndex += 1
            }

            // Save chunk if we have content
            if !currentChunk.isEmpty {
                chunks.append(TextChunk(text: currentChunk, index: chunkIndex))
                chunkIndex += 1

                // Move forward with overlap
                // Skip ahead by (sentences in chunk - overlap)
                let advance = max(1, sentencesInChunk - overlapSentences)
                sentenceIndex += advance
            } else {
                // Prevent infinite loop
                sentenceIndex += 1
            }
        }

        return chunks.isEmpty ? [TextChunk(text: text, index: 0)] : chunks
    }

    /// Split a very long sentence into smaller pieces
    private func splitLongSentence(_ sentence: String, maxChunkSize: Int) -> [String] {
        var chunks: [String] = []
        var remaining = sentence

        while remaining.count > maxChunkSize {
            let endIndex = remaining.index(remaining.startIndex, offsetBy: maxChunkSize)
            let chunk = String(remaining[..<endIndex])
            chunks.append(chunk)
            remaining = String(remaining[endIndex...])
        }

        if !remaining.isEmpty {
            chunks.append(remaining)
        }

        return chunks
    }

    /// Original paragraph-based chunking (kept as alternative)
    private func chunkByParagraphs(_ text: String, maxChunkSize: Int = 512) -> [TextChunk] {
        // Split by paragraphs (double newline)
        let paragraphs = text
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var chunks: [TextChunk] = []
        var currentChunk = ""
        var chunkIndex = 0

        for paragraph in paragraphs {
            // If paragraph itself is too long, split by sentences
            if paragraph.count > maxChunkSize {
                // Save current chunk if exists
                if !currentChunk.isEmpty {
                    chunks.append(TextChunk(text: currentChunk, index: chunkIndex))
                    chunkIndex += 1
                    currentChunk = ""
                }

                // Split long paragraph into sentences
                let sentences = splitIntoSentences(paragraph)
                for sentence in sentences {
                    if currentChunk.count + sentence.count > maxChunkSize {
                        // Save current chunk
                        if !currentChunk.isEmpty {
                            chunks.append(TextChunk(text: currentChunk, index: chunkIndex))
                            chunkIndex += 1
                        }
                        currentChunk = sentence
                    } else {
                        currentChunk += (currentChunk.isEmpty ? "" : " ") + sentence
                    }
                }
            } else {
                // Try to add paragraph to current chunk
                let potentialChunk = currentChunk.isEmpty ? paragraph : currentChunk + "\n\n" + paragraph

                if potentialChunk.count > maxChunkSize {
                    // Save current chunk and start new one
                    if !currentChunk.isEmpty {
                        chunks.append(TextChunk(text: currentChunk, index: chunkIndex))
                        chunkIndex += 1
                    }
                    currentChunk = paragraph
                } else {
                    currentChunk = potentialChunk
                }
            }
        }

        // Save final chunk
        if !currentChunk.isEmpty {
            chunks.append(TextChunk(text: currentChunk, index: chunkIndex))
        }

        // If no chunks created (very short text), return whole text as single chunk
        if chunks.isEmpty {
            chunks.append(TextChunk(text: text, index: 0))
        }

        return chunks
    }

    /// Split text into sentences (simple approach)
    private func splitIntoSentences(_ text: String) -> [String] {
        // Split on . ! ? followed by space or newline
        let pattern = "[.!?]\\s+"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [text]
        }

        let nsString = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsString.length))

        var sentences: [String] = []
        var lastIndex = 0

        for match in matches {
            let range = match.range
            let sentence = nsString.substring(with: NSRange(location: lastIndex, length: range.location - lastIndex + range.length))
            let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                sentences.append(trimmed)
            }
            lastIndex = range.location + range.length
        }

        // Add remaining text
        if lastIndex < nsString.length {
            let remaining = nsString.substring(from: lastIndex).trimmingCharacters(in: .whitespacesAndNewlines)
            if !remaining.isEmpty {
                sentences.append(remaining)
            }
        }

        return sentences.isEmpty ? [text] : sentences
    }
}
