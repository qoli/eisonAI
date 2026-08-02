//
//  HistoryModels.swift
//  iOS (App)
//
//  Created by 黃佁媛 on 2024/4/10.
//

import Foundation

enum RawGenerationState: String, Codable {
    case legacy
    case generating
    case completed
    case failed
}

struct RawHistoryItemMetadata: Codable, Identifiable {
    var v: Int
    var id: String
    var createdAt: Date
    var url: String
    var title: String
    var summaryText: String
    var modelId: String
    var tags: [String] = []
    var generationState: RawGenerationState?
    var generationError: String?

    var resolvedGenerationState: RawGenerationState {
        generationState ?? .legacy
    }

    enum CodingKeys: String, CodingKey {
        case v
        case id
        case createdAt
        case url
        case title
        case summaryText
        case modelId
        case tags
        case generationState
        case generationError
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        v = try container.decode(Int.self, forKey: .v)
        id = try container.decode(String.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        url = try container.decode(String.self, forKey: .url)
        title = try container.decode(String.self, forKey: .title)
        summaryText = try container.decode(String.self, forKey: .summaryText)
        modelId = try container.decode(String.self, forKey: .modelId)
        tags = (try container.decodeIfPresent([String].self, forKey: .tags)) ?? []
        generationState = try container.decodeIfPresent(RawGenerationState.self, forKey: .generationState)
        generationError = try container.decodeIfPresent(String.self, forKey: .generationError)
    }
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
    var tags: [String] = []
    var systemPrompt: String
    var userPrompt: String
    var modelId: String
    var readingAnchors: [ReadingAnchorChunk]?
    var tokenEstimate: Int?
    var tokenEstimator: String?
    var chunkTokenSize: Int?
    var routingThreshold: Int?
    var isLongDocument: Bool?
    var generationState: RawGenerationState?
    var generationError: String?

    var resolvedGenerationState: RawGenerationState {
        generationState ?? .legacy
    }

    init(
        v: Int,
        id: String,
        createdAt: Date,
        url: String,
        title: String,
        articleText: String,
        summaryText: String,
        tags: [String] = [],
        systemPrompt: String,
        userPrompt: String,
        modelId: String,
        readingAnchors: [ReadingAnchorChunk]? = nil,
        tokenEstimate: Int? = nil,
        tokenEstimator: String? = nil,
        chunkTokenSize: Int? = nil,
        routingThreshold: Int? = nil,
        isLongDocument: Bool? = nil,
        generationState: RawGenerationState?,
        generationError: String? = nil
    ) {
        self.v = v
        self.id = id
        self.createdAt = createdAt
        self.url = url
        self.title = title
        self.articleText = articleText
        self.summaryText = summaryText
        self.tags = tags
        self.systemPrompt = systemPrompt
        self.userPrompt = userPrompt
        self.modelId = modelId
        self.readingAnchors = readingAnchors
        self.tokenEstimate = tokenEstimate
        self.tokenEstimator = tokenEstimator
        self.chunkTokenSize = chunkTokenSize
        self.routingThreshold = routingThreshold
        self.isLongDocument = isLongDocument
        self.generationState = generationState
        self.generationError = generationError
    }

    enum CodingKeys: String, CodingKey {
        case v
        case id
        case createdAt
        case url
        case title
        case articleText
        case summaryText
        case tags
        case systemPrompt
        case userPrompt
        case modelId
        case readingAnchors
        case tokenEstimate
        case tokenEstimator
        case chunkTokenSize
        case routingThreshold
        case isLongDocument
        case generationState
        case generationError
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        v = try container.decode(Int.self, forKey: .v)
        id = try container.decode(String.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        url = try container.decode(String.self, forKey: .url)
        title = try container.decode(String.self, forKey: .title)
        articleText = try container.decode(String.self, forKey: .articleText)
        summaryText = try container.decode(String.self, forKey: .summaryText)
        tags = (try container.decodeIfPresent([String].self, forKey: .tags)) ?? []
        systemPrompt = try container.decode(String.self, forKey: .systemPrompt)
        userPrompt = try container.decode(String.self, forKey: .userPrompt)
        modelId = try container.decode(String.self, forKey: .modelId)
        readingAnchors = try container.decodeIfPresent([ReadingAnchorChunk].self, forKey: .readingAnchors)
        tokenEstimate = try container.decodeIfPresent(Int.self, forKey: .tokenEstimate)
        tokenEstimator = try container.decodeIfPresent(String.self, forKey: .tokenEstimator)
        chunkTokenSize = try container.decodeIfPresent(Int.self, forKey: .chunkTokenSize)
        routingThreshold = try container.decodeIfPresent(Int.self, forKey: .routingThreshold)
        isLongDocument = try container.decodeIfPresent(Bool.self, forKey: .isLongDocument)
        generationState = try container.decodeIfPresent(RawGenerationState.self, forKey: .generationState)
        generationError = try container.decodeIfPresent(String.self, forKey: .generationError)
    }
}

struct RawHistoryEntry: Identifiable, Hashable {
    var fileURL: URL
    var metadata: RawHistoryItemMetadata

    var id: String { fileURL.lastPathComponent }

    static func == (lhs: RawHistoryEntry, rhs: RawHistoryEntry) -> Bool {
        lhs.fileURL == rhs.fileURL
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(fileURL)
    }
}
