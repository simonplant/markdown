import Testing
import Foundation
@testable import EMAI
@testable import EMCore

@Suite("ModelLoader")
struct ModelLoaderTests {

    private func makeLoader(withModel: Bool = false) throws -> (ModelLoader, ModelStorageManager) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("emai-loader-test-\(UUID().uuidString)")
        let storage = ModelStorageManager(modelDirectory: dir)
        if withModel {
            try storage.ensureDirectoryExists()
            try Data(repeating: 0x42, count: 4096).write(to: storage.modelFileURL)
        }
        return (ModelLoader(storage: storage), storage)
    }

    @Test("Initially not loaded")
    func initiallyNotLoaded() async throws {
        let (loader, _) = try makeLoader()
        let loaded = await loader.isLoaded
        #expect(loaded == false)
    }

    @Test("loadModel throws when model not present")
    func loadMissingModelThrows() async throws {
        let (loader, _) = try makeLoader(withModel: false)
        do {
            try await loader.loadModel()
            Issue.record("Expected modelNotDownloaded error")
        } catch let error as EMError {
            if case .ai(.modelNotDownloaded) = error {
                // Expected
            } else {
                Issue.record("Unexpected error: \(error)")
            }
        }
    }

    @Test("loadModel succeeds when model file exists")
    func loadModelSucceeds() async throws {
        let (loader, _) = try makeLoader(withModel: true)
        try await loader.loadModel()
        let loaded = await loader.isLoaded
        #expect(loaded == true)
        let footprint = await loader.modelMemoryFootprint
        #expect(footprint == 4096)
    }

    @Test("loadModel is idempotent")
    func loadModelIdempotent() async throws {
        let (loader, _) = try makeLoader(withModel: true)
        try await loader.loadModel()
        try await loader.loadModel() // Second call should not crash
        let loaded = await loader.isLoaded
        #expect(loaded == true)
    }

    @Test("unloadModel resets state")
    func unloadResetsState() async throws {
        let (loader, _) = try makeLoader(withModel: true)
        try await loader.loadModel()
        await loader.unloadModel()
        let loaded = await loader.isLoaded
        #expect(loaded == false)
        let footprint = await loader.modelMemoryFootprint
        #expect(footprint == 0)
    }

    @Test("Memory budget constant is 100MB")
    func memoryBudget() {
        #expect(ModelLoader.memoryBudgetBytes == 100 * 1024 * 1024)
    }
}
