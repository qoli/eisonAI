import Foundation

struct MLXCatalogModel: Codable, Hashable, Identifiable {
    enum Recommendation: String {
        case recommended
        case caution
        case likelyTooLarge
        case unknown

        var label: String {
            switch self {
            case .recommended:
                return "Recommended"
            case .caution:
                return "Caution"
            case .likelyTooLarge:
                return "Likely Too Large"
            case .unknown:
                return "Unknown"
            }
        }
    }

    struct CardData: Codable, Hashable {
        let baseModel: String?
        let pipelineTag: String?

        enum CodingKeys: String, CodingKey {
            case baseModel = "base_model"
            case pipelineTag = "pipeline_tag"
        }
    }

    struct SafeTensorInfo: Codable, Hashable {
        let parameters: [String: Int64]?
        let total: Int64?
    }

    let id: String
    let pipelineTag: String
    let baseModel: String?
    let lastModified: Date?
    let estimatedParameterCount: Double?
    let rawSafeTensorTotal: Int64?

    var displayName: String {
        id.components(separatedBy: "/").last ?? id
    }

    var estimatedParameterLabel: String {
        guard let estimatedParameterCount else { return "Unknown" }
        let billion = estimatedParameterCount / 1_000_000_000
        if billion >= 1 {
            return String(format: "~%.1fB", billion)
        }
        let million = estimatedParameterCount / 1_000_000
        return String(format: "~%.0fM", million)
    }

    func recommendation(forRAMGiB ramGiB: Double) -> Recommendation {
        guard let estimatedParameterCount else { return .unknown }
        let billion = estimatedParameterCount / 1_000_000_000

        switch ramGiB {
        case ..<6:
            if billion <= 3 { return .caution }
            return .likelyTooLarge
        case ..<8:
            if billion <= 3 { return .recommended }
            if billion <= 8 { return .caution }
            return .likelyTooLarge
        case ..<12:
            if billion <= 8 { return .recommended }
            if billion <= 16 { return .caution }
            return .likelyTooLarge
        case ..<18:
            if billion <= 14 { return .recommended }
            if billion <= 28 { return .caution }
            return .likelyTooLarge
        default:
            if billion <= 28 { return .recommended }
            if billion <= 48 { return .caution }
            return .likelyTooLarge
        }
    }

    init(
        id: String,
        pipelineTag: String,
        baseModel: String?,
        lastModified: Date?,
        estimatedParameterCount: Double?,
        rawSafeTensorTotal: Int64?
    ) {
        self.id = id
        self.pipelineTag = pipelineTag
        self.baseModel = baseModel
        self.lastModified = lastModified
        self.estimatedParameterCount = estimatedParameterCount
        self.rawSafeTensorTotal = rawSafeTensorTotal
    }
}

struct InstalledMLXModel: Codable, Hashable, Identifiable {
    let id: String
    let pipelineTag: String
    let baseModel: String?
    let lastModified: Date?
    let estimatedParameterCount: Double?

    init(model: MLXCatalogModel) {
        id = model.id
        pipelineTag = model.pipelineTag
        baseModel = model.baseModel
        lastModified = model.lastModified
        estimatedParameterCount = model.estimatedParameterCount
    }
}

struct MLXModelCatalogService {
    private let session: URLSession
    private let decoder: JSONDecoder
    private let iso8601: ISO8601DateFormatter

    init(session: URLSession = .shared) {
        self.session = session
        self.decoder = JSONDecoder()
        self.iso8601 = ISO8601DateFormatter()
        self.iso8601.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    func fetchCatalog(limit: Int = 100) async throws -> [MLXCatalogModel] {
        let pipelineTags = ["text-generation", "image-text-to-text", "any-to-any"]
        var merged: [String: MLXCatalogModel] = [:]

        for pipelineTag in pipelineTags {
            let items = try await fetchModels(
                author: "mlx-community",
                pipelineTag: pipelineTag,
                limit: limit
            )
            for item in items {
                if let current = merged[item.id] {
                    let currentDate = current.lastModified ?? .distantPast
                    let newDate = item.lastModified ?? .distantPast
                    if newDate > currentDate {
                        merged[item.id] = item
                    }
                } else {
                    merged[item.id] = item
                }
            }
        }

        return merged.values.sorted {
            ($0.lastModified ?? .distantPast) > ($1.lastModified ?? .distantPast)
        }
    }

    func fetchModel(repoID: String) async throws -> MLXCatalogModel {
        var components = URLComponents(string: "https://huggingface.co/api/models/\(repoID)")!
        components.queryItems = [
            URLQueryItem(name: "expand[]", value: "cardData"),
            URLQueryItem(name: "expand[]", value: "safetensors"),
            URLQueryItem(name: "expand[]", value: "lastModified"),
        ]
        let (data, response) = try await session.data(from: components.url!)
        try validate(response: response, data: data)
        let raw = try decoder.decode(HuggingFaceModelResponse.self, from: data)
        return raw.toCatalogModel(using: iso8601)
    }

    private func fetchModels(
        author: String,
        pipelineTag: String,
        limit: Int
    ) async throws -> [MLXCatalogModel] {
        var components = URLComponents(string: "https://huggingface.co/api/models")!
        components.queryItems = [
            URLQueryItem(name: "author", value: author),
            URLQueryItem(name: "pipeline_tag", value: pipelineTag),
            URLQueryItem(name: "sort", value: "lastModified"),
            URLQueryItem(name: "direction", value: "-1"),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "expand[]", value: "cardData"),
            URLQueryItem(name: "expand[]", value: "safetensors"),
            URLQueryItem(name: "expand[]", value: "lastModified"),
        ]
        let (data, response) = try await session.data(from: components.url!)
        try validate(response: response, data: data)
        let raw = try decoder.decode([HuggingFaceModelResponse].self, from: data)
        return raw.map { $0.toCatalogModel(using: iso8601) }
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw CatalogError.invalidResponse("Unexpected response.")
        }
        guard (200 ... 299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw CatalogError.invalidResponse("HTTP \(http.statusCode): \(body.prefix(160))")
        }
    }
}

extension MLXModelCatalogService {
    enum CatalogError: LocalizedError {
        case invalidResponse(String)

        var errorDescription: String? {
            switch self {
            case let .invalidResponse(message):
                return message
            }
        }
    }

    private struct HuggingFaceModelResponse: Codable {
        let id: String
        let pipelineTag: String?
        let cardData: MLXCatalogModel.CardData?
        let safetensors: MLXCatalogModel.SafeTensorInfo?
        let lastModified: String?

        enum CodingKeys: String, CodingKey {
            case id
            case pipelineTag = "pipeline_tag"
            case cardData
            case safetensors
            case lastModified
        }

        func toCatalogModel(using formatter: ISO8601DateFormatter) -> MLXCatalogModel {
            let parsedDate = lastModified.flatMap { formatter.date(from: $0) }
            let parameterCount = estimateParameterCount(from: safetensors?.parameters)
            return MLXCatalogModel(
                id: id,
                pipelineTag: pipelineTag ?? cardData?.pipelineTag ?? "unknown",
                baseModel: cardData?.baseModel,
                lastModified: parsedDate,
                estimatedParameterCount: parameterCount,
                rawSafeTensorTotal: safetensors?.total
            )
        }

        private func estimateParameterCount(from parameters: [String: Int64]?) -> Double? {
            guard let parameters, !parameters.isEmpty else { return nil }

            let bf16 = Double(parameters["BF16"] ?? 0)
            let f16 = Double(parameters["F16"] ?? 0)
            let f32 = Double(parameters["F32"] ?? 0)
            let u32 = Double(parameters["U32"] ?? 0)
            let u8 = Double(parameters["U8"] ?? 0)

            let total = bf16 + f16 + f32 + (u32 * 8) + (u8 * 2)
            return total > 0 ? total : nil
        }
    }
}
