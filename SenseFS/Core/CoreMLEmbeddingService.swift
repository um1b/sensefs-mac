//
//  CoreMLEmbeddingService.swift
//  CoreML-based embedding service using multilingual-e5-small
//
//  Uses Swift Package: https://github.com/huggingface/swift-transformers
//

import Foundation
import CoreML
import Tokenizers
import Hub

/// Embedding service using CoreML model (multilingual-e5-small)
actor CoreMLEmbeddingService {
    static let shared = CoreMLEmbeddingService()

    private nonisolated(unsafe) var model: MLModel?
    private nonisolated(unsafe) var optimizedModel: MLModel? // Neural Engine optimized version
    private var tokenizer: Tokenizer?
    private let maxSequenceLength = 512
    private let embeddingDimension = 384
    private var isOptimizedModelReady = false

    private init() {
        print("🧠 CoreML Embedding Service initializing...")
        Task {
            await loadModel()
        }
    }

    // MARK: - Model Loading

    private func loadModel() async {
        do {
            let startTime = Date()

            // Load CoreML model
            guard let modelURL = getModelURL() else {
                print("❌ CoreML model not found")
                return
            }

            print("📦 Loading CoreML model from: \(modelURL.path)")

            // Get or compile the model (with caching)
            let compiledModelURL = try await getOrCompileModel(modelURL)
            let compileTime = Date().timeIntervalSince(startTime)
            print("⏱️ Compile/cache time: \(String(format: "%.2f", compileTime))s")

            // Use CPU-only for faster loading (Neural Engine adds ~5-8s at load time)
            // Inference is still fast on CPU for small models like e5-small
            let config = MLModelConfiguration()
            config.computeUnits = .cpuOnly // Fastest loading, still good performance

            print("📥 Loading compiled model...")
            let loadStart = Date()
            model = try MLModel(contentsOf: compiledModelURL, configuration: config)
            let loadTime = Date().timeIntervalSince(loadStart)
            print("⏱️ Model load time: \(String(format: "%.2f", loadTime))s")

            // Load tokenizer
            guard let tokenizerURL = getTokenizerURL() else {
                print("❌ Tokenizer not found")
                return
            }

            print("📖 Loading tokenizer from: \(tokenizerURL.path)")

            // Load tokenizer config and data files
            let tokenizerJsonURL = tokenizerURL.appendingPathComponent("tokenizer.json")
            let configURL = tokenizerURL.appendingPathComponent("tokenizer_config.json")

            guard FileManager.default.fileExists(atPath: tokenizerJsonURL.path) else {
                print("❌ tokenizer.json not found at: \(tokenizerJsonURL.path)")
                return
            }

            guard FileManager.default.fileExists(atPath: configURL.path) else {
                print("❌ tokenizer_config.json not found at: \(configURL.path)")
                return
            }

            print("📄 Loading tokenizer files...")
            let configData = try Data(contentsOf: configURL)
            let tokenizerData = try Data(contentsOf: tokenizerJsonURL)

            let tokenizerConfigObj = try JSONDecoder().decode(Config.self, from: configData)
            let tokenizerDataObj = try JSONDecoder().decode(Config.self, from: tokenizerData)

            print("📄 Initializing PreTrainedTokenizer...")
            // Use PreTrainedTokenizer which works with various tokenizer types including XLMRoberta
            tokenizer = try PreTrainedTokenizer(tokenizerConfig: tokenizerConfigObj, tokenizerData: tokenizerDataObj)

            let totalTime = Date().timeIntervalSince(startTime)
            print("✅ CoreML Embedding Service ready in \(String(format: "%.2f", totalTime))s")
            print("   - Model: multilingual-e5-small (FP16)")
            print("   - Dimension: \(embeddingDimension)")
            print("   - Max sequence length: \(maxSequenceLength)")
            print("   - Compute units: CPU (optimized for fast loading)")

            // Load Neural Engine optimized model in background
            Task.detached(priority: .utility) { [weak self] in
                await self?.loadOptimizedModel(compiledModelURL)
            }

        } catch {
            print("❌ Failed to load model/tokenizer: \(error)")
        }
    }

    /// Load Neural Engine optimized model in background (non-blocking)
    private func loadOptimizedModel(_ compiledModelURL: URL) async {
        do {
            print("🔧 Loading Neural Engine optimized model in background...")
            let startTime = Date()

            let config = MLModelConfiguration()
            config.computeUnits = .all // Neural Engine + GPU + CPU

            let loadedModel = try MLModel(contentsOf: compiledModelURL, configuration: config)
            let loadTime = Date().timeIntervalSince(startTime)

            // Update actor-isolated properties
            optimizedModel = loadedModel
            isOptimizedModelReady = true
            print("✅ Neural Engine model ready in \(String(format: "%.2f", loadTime))s - switching to optimized inference")
        } catch {
            print("⚠️ Failed to load optimized model (continuing with CPU): \(error)")
        }
    }

    /// Get or compile the model with persistent caching
    private func getOrCompileModel(_ modelURL: URL) async throws -> URL {
        // If already compiled (.mlmodelc), return directly
        if modelURL.pathExtension == "mlmodelc" {
            print("✅ Using pre-compiled model from bundle")
            return modelURL
        }

        // Cache compiled model in Application Support
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let cacheDir = appSupport.appendingPathComponent("com.sensefs.app/ModelCache")

        // Create cache directory if needed
        try? fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        let cachedModelURL = cacheDir.appendingPathComponent("multilingual-e5-small-fp16.mlmodelc")

        // Check if cached compiled model exists
        if fileManager.fileExists(atPath: cachedModelURL.path) {
            print("📦 Using cached compiled model")
            return cachedModelURL
        }

        // Compile and cache
        print("🔨 Compiling model (first run only)...")
        let tempCompiledURL = try await MLModel.compileModel(at: modelURL)

        // Move to persistent cache location
        try? fileManager.removeItem(at: cachedModelURL) // Remove if exists
        try fileManager.copyItem(at: tempCompiledURL, to: cachedModelURL)

        print("💾 Compiled model cached to: \(cachedModelURL.path)")
        return cachedModelURL
    }

    private func getModelURL() -> URL? {
        // First try to load compiled model from app bundle (Xcode auto-compiles .mlpackage to .mlmodelc)
        if let bundleURL = Bundle.main.url(forResource: "multilingual-e5-small-fp16", withExtension: "mlmodelc") {
            return bundleURL
        }

        // Fallback to .mlpackage if not compiled yet
        if let bundleURL = Bundle.main.url(forResource: "multilingual-e5-small-fp16", withExtension: "mlpackage") {
            return bundleURL
        }

        // Try Application Support directory
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let modelsDir = appSupport.appendingPathComponent("com.sensefs.app/Models")
        let modelURL = modelsDir.appendingPathComponent("multilingual-e5-small-fp16.mlpackage")

        if fileManager.fileExists(atPath: modelURL.path) {
            return modelURL
        }

        // Development fallback (parent directory of project)
        let projectDir = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().path.components(separatedBy: "/").dropLast().joined(separator: "/")
        if !projectDir.isEmpty {
            let devModelsPath = "/\(projectDir)/Models/multilingual-e5-small-fp16.mlpackage"
            if fileManager.fileExists(atPath: devModelsPath) {
                print("⚠️ Using development model path: \(devModelsPath)")
                return URL(fileURLWithPath: devModelsPath)
            }
        }

        return nil
    }

    private func getTokenizerURL() -> URL? {
        let fileManager = FileManager.default

        // First try to load from app bundle
        if let bundleURL = Bundle.main.resourceURL?.appendingPathComponent("e5-tokenizer") {
            if fileManager.fileExists(atPath: bundleURL.path) {
                return bundleURL
            }
        }

        // Try Application Support directory
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let tokenizerDir = appSupport.appendingPathComponent("com.sensefs.app/Models/e5-tokenizer")

        if fileManager.fileExists(atPath: tokenizerDir.path) {
            return tokenizerDir
        }

        // Development fallback (parent directory of project)
        let projectDir = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().path.components(separatedBy: "/").dropLast().joined(separator: "/")
        if !projectDir.isEmpty {
            let devTokenizerPath = "/\(projectDir)/Models/e5-tokenizer"
            if fileManager.fileExists(atPath: devTokenizerPath) {
                print("⚠️ Using development tokenizer path: \(devTokenizerPath)")
                return URL(fileURLWithPath: devTokenizerPath)
            }
        }

        return nil
    }

    // MARK: - Model Info

    func getModelInfo() -> (dimension: Int, maxLength: Int, isLoaded: Bool) {
        return (embeddingDimension, maxSequenceLength, model != nil && tokenizer != nil)
    }

    // MARK: - Embedding Generation

    /// Generate embedding for a single text
    func embed(_ text: String) async throws -> (vector: [Float], language: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CoreMLEmbeddingError.emptyText
        }

        guard let model = model, let tokenizer = tokenizer else {
            throw CoreMLEmbeddingError.modelNotLoaded
        }

        // Tokenize input
        let encoding = tokenizer.encode(text: text)

        // Pad or truncate to max_sequence_length
        var inputIds = encoding
        var attentionMask = Array(repeating: 1, count: encoding.count)

        if inputIds.count > maxSequenceLength {
            inputIds = Array(inputIds.prefix(maxSequenceLength))
            attentionMask = Array(attentionMask.prefix(maxSequenceLength))
        } else {
            let padding = maxSequenceLength - inputIds.count
            inputIds.append(contentsOf: Array(repeating: 1, count: padding)) // PAD token ID
            attentionMask.append(contentsOf: Array(repeating: 0, count: padding))
        }

        // Create MLMultiArray inputs
        guard let inputIdsArray = try? MLMultiArray(shape: [1, maxSequenceLength as NSNumber], dataType: .int32),
              let attentionMaskArray = try? MLMultiArray(shape: [1, maxSequenceLength as NSNumber], dataType: .int32) else {
            throw CoreMLEmbeddingError.invalidInput
        }

        // Fill arrays
        for i in 0..<maxSequenceLength {
            inputIdsArray[i] = NSNumber(value: inputIds[i])
            attentionMaskArray[i] = NSNumber(value: attentionMask[i])
        }

        // Create input feature provider
        let input = try MLDictionaryFeatureProvider(dictionary: [
            "input_ids": MLFeatureValue(multiArray: inputIdsArray),
            "attention_mask": MLFeatureValue(multiArray: attentionMaskArray)
        ])

        // Use optimized model if ready, otherwise use CPU model
        let activeModel = isOptimizedModelReady ? optimizedModel : model
        guard let activeModel = activeModel else {
            throw CoreMLEmbeddingError.modelNotLoaded
        }

        // Run prediction
        let output = try await activeModel.prediction(from: input)

        // Extract embeddings
        guard let embeddingsMultiArray = output.featureValue(for: "embeddings")?.multiArrayValue else {
            throw CoreMLEmbeddingError.invalidOutput
        }

        // Convert MLMultiArray to [Float]
        var embeddings: [Float] = []
        embeddings.reserveCapacity(embeddingDimension)

        for i in 0..<embeddingDimension {
            embeddings.append(Float(truncating: embeddingsMultiArray[i]))
        }

        // Embeddings are already normalized by the model
        return (embeddings, "multilingual")
    }

    /// Generate embeddings for multiple texts (batch processing)
    func embedBatch(_ texts: [String]) async throws -> [[Float]] {
        var results: [[Float]] = []

        for text in texts {
            let (vector, _) = try await embed(text)
            results.append(vector)
        }

        return results
    }

    // MARK: - Similarity Calculation

    /// Calculate cosine similarity between two vectors
    func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0 }

        let dotProduct = zip(a, b).map(*).reduce(0, +)
        let magnitudeA = sqrt(a.map { $0 * $0 }.reduce(0, +))
        let magnitudeB = sqrt(b.map { $0 * $0 }.reduce(0, +))

        guard magnitudeA > 0, magnitudeB > 0 else { return 0 }

        return dotProduct / (magnitudeA * magnitudeB)
    }

    // MARK: - Legacy Compatibility Methods

    /// Detect language (compatibility method - multilingual-e5-small handles all languages)
    func detectLanguage(_ text: String) async -> String? {
        return "multilingual"
    }

    /// Embed with specified language (compatibility method)
    func embedWithLanguage(_ text: String, language: String) async -> [Float]? {
        do {
            let result = try await embed(text)
            return result.vector
        } catch {
            print("⚠️ Failed to generate embedding: \(error)")
            return nil
        }
    }
}

// MARK: - Error Types

enum CoreMLEmbeddingError: LocalizedError {
    case modelNotLoaded
    case emptyText
    case invalidInput
    case invalidOutput
    case tokenizationError

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "CoreML model or tokenizer not loaded"
        case .emptyText:
            return "Empty text provided"
        case .invalidInput:
            return "Invalid input for CoreML model"
        case .invalidOutput:
            return "Invalid output from CoreML model"
        case .tokenizationError:
            return "Failed to tokenize input text"
        }
    }
}
