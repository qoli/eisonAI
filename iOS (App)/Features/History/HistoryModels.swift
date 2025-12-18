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
}

struct RawHistoryEntry: Identifiable {
    var fileURL: URL
    var metadata: RawHistoryItemMetadata

    var id: String { fileURL.lastPathComponent }
}
