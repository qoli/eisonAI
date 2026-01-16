import Foundation

enum LongDocumentDefaults {
    static let autoStrategyThresholdValue = 1792
    static let allowedChunkSizes: [Int] = [1792]
    static let allowedChunkSizeSet: Set<Int> = Set(allowedChunkSizes)
    static let fallbackChunkSize = 1792
    static let routingThresholdValue = 2048

    static let allowedMaxChunkCounts: [Int] = [4, 5, 6, 7]
    static let allowedMaxChunkCountSet: Set<Int> = Set(allowedMaxChunkCounts)
    static let fallbackMaxChunkCount = 5
}
