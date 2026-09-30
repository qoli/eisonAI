import XCTest
@testable import eisonAI

@MainActor
final class LongDocumentFallbackTests: XCTestCase {
    func testLegacyMLXBackendMigratesToAppleLocalSelection() {
        let suiteName = "GenerationBackendTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("mlx", forKey: AppConfig.legacyGenerationBackendKey)

        let store = GenerationBackendSettingsStore(
            defaults: defaults,
            appleAvailability: { .available }
        )

        XCTAssertEqual(store.loadSelectedBackend(), .local)
        XCTAssertEqual(store.resolveExecutionBackend(tokenCount: 100), .appleIntelligence)
    }

    func testAutoUsesBYOKWhenAppleIntelligenceIsUnavailable() {
        let suiteName = "GenerationBackendTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = GenerationBackendSettingsStore(
            defaults: defaults,
            appleAvailability: { .unavailable("Unavailable for test") }
        )
        store.saveSelectedBackend(.auto)

        XCTAssertEqual(store.resolveExecutionBackend(tokenCount: 100), .byok)
    }

    func testAutoUsesAppleIntelligenceForShortInputWhenAvailable() {
        let suiteName = "GenerationBackendTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = GenerationBackendSettingsStore(
            defaults: defaults,
            appleAvailability: { .available }
        )
        store.saveSelectedBackend(.auto)

        XCTAssertEqual(store.resolveExecutionBackend(tokenCount: 100), .appleIntelligence)
    }

    func testExplicitLocalDoesNotFallBackToBYOKWhenAppleIntelligenceIsUnavailable() {
        let suiteName = "GenerationBackendTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = GenerationBackendSettingsStore(
            defaults: defaults,
            appleAvailability: { .unavailable("Unavailable for test") }
        )
        store.saveSelectedBackend(.local)

        XCTAssertEqual(store.resolveExecutionBackend(tokenCount: 100), .appleIntelligence)
        XCTAssertThrowsError(try store.validateSelectedBackendForGeneration())
    }

    func testIsContextWindowExceededFalseForOtherErrors() {
        let viewModel = ClipboardKeyPointViewModel()
        let error = NSError(domain: "test", code: 2)
        XCTAssertFalse(viewModel.isContextWindowExceeded(error))
    }

    func testNextLowerChunkTokenSize() {
        let viewModel = ClipboardKeyPointViewModel()
        let sizes = [2000, 2200, 2600, 3000]

        XCTAssertEqual(viewModel.nextLowerChunkTokenSize(current: 2600, allowedSizes: sizes), 2200)
        XCTAssertNil(viewModel.nextLowerChunkTokenSize(current: 2000, allowedSizes: sizes))
        XCTAssertEqual(viewModel.nextLowerChunkTokenSize(current: 2500, allowedSizes: sizes), 2200)
    }

    func testSliceTextClampsBounds() {
        let viewModel = ClipboardKeyPointViewModel()
        let text = "abcdef"

        XCTAssertEqual(viewModel.sliceText(text, startUTF16: 1, endUTF16: 4), "bcd")
        XCTAssertEqual(viewModel.sliceText(text, startUTF16: -3, endUTF16: 2), "ab")
        XCTAssertEqual(viewModel.sliceText(text, startUTF16: 10, endUTF16: 12), "")
    }
}
