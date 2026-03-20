import Foundation
import os
import EMCore

/// Loads and manages the on-device AI model for inference per [A-008].
/// Memory-maps the model to minimize RAM impact per AC-5.
/// Designed as a contained, removable component — may become unnecessary if Apple ships platform AI.
public actor ModelLoader {
    /// Whether a model is currently loaded and ready for inference.
    public private(set) var isLoaded: Bool = false

    /// Memory footprint of the loaded model in bytes.
    public private(set) var modelMemoryFootprint: Int64 = 0

    private let storage: ModelStorageManager
    private let logger = Logger(subsystem: "com.easymarkdown.emai", category: "model")

    /// Maximum memory budget for model loading per AC-5 (100MB editing session budget).
    /// The model itself is memory-mapped separately and does not count against this.
    public static let memoryBudgetBytes: Int64 = 100 * 1024 * 1024

    /// Handle to the memory-mapped model data.
    private var modelData: Data?

    public init(storage: ModelStorageManager) {
        self.storage = storage
    }

    /// Loads the model into memory using memory-mapping.
    /// Memory-mapped to minimize RAM impact — the OS pages in only what's needed per AC-5.
    public func loadModel() async throws {
        guard !isLoaded else { return }
        guard storage.isModelPresent else {
            throw EMError.ai(.modelNotDownloaded)
        }

        logger.info("Loading model from \(self.storage.modelFileURL.lastPathComponent)")

        // Memory-map the model file — OS manages paging, minimizes RSS
        let data = try Data(
            contentsOf: storage.modelFileURL,
            options: [.mappedIfSafe, .uncached]
        )

        modelData = data
        modelMemoryFootprint = Int64(data.count)
        isLoaded = true

        logger.info("Model loaded (memory-mapped, \(data.count) bytes)")
    }

    /// Unloads the model from memory.
    public func unloadModel() {
        modelData = nil
        isLoaded = false
        modelMemoryFootprint = 0
        logger.info("Model unloaded")
    }

    /// Runs inference on the loaded model, streaming tokens.
    /// First token target: <500ms per [D-PERF-4] and AC-4.
    public func runInference(prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            guard isLoaded, modelData != nil else {
                continuation.finish(throwing: EMError.ai(.modelNotDownloaded))
                return
            }

            // Inference implementation depends on SPIKE-005 results.
            // This is the integration point for MLX Swift or Core ML.
            // The architecture is in place — the actual model format and
            // inference runtime will be determined by the spike.
            //
            // When implementing:
            // 1. Tokenize input with the model's tokenizer
            // 2. Run forward pass, streaming output tokens
            // 3. Measure first token latency with os_signpost
            // 4. Target <500ms first token on A16+/M1+
            //
            // For now, this signals that inference is not yet available
            // until the spike completes and a real model is integrated.
            continuation.finish(throwing: EMError.ai(.modelNotDownloaded))
        }
    }
}
