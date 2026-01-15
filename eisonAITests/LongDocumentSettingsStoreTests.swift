import XCTest
@testable import eisonAI

final class LongDocumentSettingsStoreTests: XCTestCase {
    private var suiteName: String = ""
    private var defaults: UserDefaults?

    override func setUp() {
        super.setUp()
        suiteName = "eisonAITests.LongDocumentSettingsStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults?.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        if let suite = defaults {
            suite.removePersistentDomain(forName: suiteName)
        }
        defaults = nil
        super.tearDown()
    }

    func testRoutingThresholdIsFixed() {
        let store = LongDocumentSettingsStore(defaults: defaults)
        XCTAssertEqual(store.routingThreshold(), 2600)
    }

    func testChunkTokenSizeFallsBackWhenInvalid() {
        defaults?.set(1234, forKey: AppConfig.longDocumentChunkTokenSizeKey)
        let store = LongDocumentSettingsStore(defaults: defaults)
        XCTAssertEqual(store.chunkTokenSize(), 2000)
    }

    func testSetChunkTokenSizeClampsToAllowedValues() {
        let store = LongDocumentSettingsStore(defaults: defaults)
        store.setChunkTokenSize(2200)
        XCTAssertEqual(store.chunkTokenSize(), 2200)

        store.setChunkTokenSize(9999)
        XCTAssertEqual(store.chunkTokenSize(), 2000)
    }

    func testMaxChunkCountFallbackAndClamp() {
        defaults?.set(1, forKey: AppConfig.longDocumentMaxChunkCountKey)
        let store = LongDocumentSettingsStore(defaults: defaults)
        XCTAssertEqual(store.maxChunkCount(), 5)

        store.setMaxChunkCount(6)
        XCTAssertEqual(store.maxChunkCount(), 6)

        store.setMaxChunkCount(99)
        XCTAssertEqual(store.maxChunkCount(), 5)
    }
}
