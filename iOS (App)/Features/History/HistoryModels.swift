//
//  HistoryModels.swift
//  iOS (App)
//
//  Created by 黃佁媛 on 2024/4/10.
//

import Foundation

struct RawHistoryItemMetadata: Codable, Identifiable {
    var v: Int
    var id: String
    var createdAt: Date
    var url: String
    var title: String
    var summaryText: String
    var modelId: String
}

struct ReadingAnchorChunk: Codable, Identifiable, Hashable {
    var index: Int
    var tokenCount: Int
    var text: String
    var startUTF16: Int?
    var endUTF16: Int?

    var id: Int { index }
}

struct RawHistoryItem: Codable, Identifiable {
    var v: Int
    var id: String
    var createdAt: Date
    var url: String
    var title: String
    var articleText: String
    var summaryText: String
    var systemPrompt: String
    var userPrompt: String
    var modelId: String
    var readingAnchors: [ReadingAnchorChunk]?
    var tokenEstimate: Int?
    var tokenEstimator: String?
    var chunkTokenSize: Int?
    var routingThreshold: Int?
    var isLongDocument: Bool?
}

struct RawHistoryEntry: Identifiable {
    var fileURL: URL
    var metadata: RawHistoryItemMetadata

    var id: String { fileURL.lastPathComponent }
}
