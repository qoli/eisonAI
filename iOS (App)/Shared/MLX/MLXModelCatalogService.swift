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

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            pipelineTag = try container.decodeIfPresent(String.self, forKey: .pipelineTag)

            if let value = try? container.decode(String.self, forKey: .baseModel) {
                baseModel = value
            } else if let values = try? container.decode([String].self, forKey: .baseModel) {
                baseModel = values.first
            } else {
                baseModel = nil
            }
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
        guard ramGiB > 0, let requiredGiB = estimatedRuntimeMemoryGiB, requiredGiB > 0 else {
            return .unknown
        }

        let headroomRatio = ramGiB / requiredGiB
        if headroomRatio >= 1.75 {
            return .recommended
        }
        if headroomRatio >= 1.15 {
            return .caution
        }
        return .likelyTooLarge
    }

    private var estimatedRuntimeMemoryGiB: Double? {
        let gib = 1024.0 * 1024.0 * 1024.0

        if let rawSafeTensorTotal {
            let weightGiB = Double(rawSafeTensorTotal) / gib
            return (weightGiB * 2.4) + 2.0
        }

        guard let estimatedParameterCount else { return nil }

        // Fallback when the Hub response omits total safetensor bytes.
        let fallbackWeightGiB = max((estimatedParameterCount / 1_000_000_000) * 0.25, 0.5)
        return (fallbackWeightGiB * 2.4) + 2.0
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
    private let iso8601WithoutFractionalSeconds: ISO8601DateFormatter

    init(session: URLSession = .shared) {
        self.session = session
        self.decoder = JSONDecoder()
        self.iso8601 = ISO8601DateFormatter()
        self.iso8601.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.iso8601WithoutFractionalSeconds = ISO8601DateFormatter()
        self.iso8601WithoutFractionalSeconds.formatOptions = [.withInternetDateTime]
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
        return try decodeModel(from: data)
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
        return try decodeModels(from: data)
    }

    func decodeModel(from data: Data) throws -> MLXCatalogModel {
        let raw = try decoder.decode(HuggingFaceModelResponse.self, from: data)
        return raw.toCatalogModel(
            using: iso8601,
            fallbackFormatter: iso8601WithoutFractionalSeconds
        )
    }

    func decodeModels(from data: Data) throws -> [MLXCatalogModel] {
        let raw = try decoder.decode([HuggingFaceModelResponse].self, from: data)
        return raw.map {
            $0.toCatalogModel(
                using: iso8601,
                fallbackFormatter: iso8601WithoutFractionalSeconds
            )
        }
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

        func toCatalogModel(
            using formatter: ISO8601DateFormatter,
            fallbackFormatter: ISO8601DateFormatter
        ) -> MLXCatalogModel {
            let parsedDate = lastModified.flatMap { value in
                formatter.date(from: value) ?? fallbackFormatter.date(from: value)
            }
            let parameterCount = estimateParameterCount(
                id: id,
                baseModel: cardData?.baseModel,
                parameters: safetensors?.parameters
            )
            return MLXCatalogModel(
                id: id,
                pipelineTag: pipelineTag ?? cardData?.pipelineTag ?? "unknown",
                baseModel: cardData?.baseModel,
                lastModified: parsedDate,
                estimatedParameterCount: parameterCount,
                rawSafeTensorTotal: safetensors?.total
            )
        }

        private func estimateParameterCount(
            id: String,
            baseModel: String?,
            parameters: [String: Int64]?
        ) -> Double? {
            if let namedCount = parseNamedParameterCount(from: [baseModel, id]) {
                return namedCount
            }

            guard let parameters, !parameters.isEmpty else { return nil }

            let u32 = Double(parameters["U32"] ?? 0)
            let u8 = Double(parameters["U8"] ?? 0)
            let bf16 = Double(parameters["BF16"] ?? 0)
            let f16 = Double(parameters["F16"] ?? 0)
            let f32 = Double(parameters["F32"] ?? 0)

            if u32 > 0 {
                return u32 * 8
            }
            if u8 > 0 {
                return u8 * 2
            }

            let denseTotal = bf16 + f16 + f32
            return denseTotal > 0 ? denseTotal : nil
        }

        private func parseNamedParameterCount(from candidates: [String?]) -> Double? {
            let pattern = #"(?:^|[^0-9])(\d+(?:\.\d+)?)\s*[bB](?=$|[^a-zA-Z])"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                return nil
            }

            var largestBillionCount = 0.0
            for candidate in candidates {
                guard let candidate, !candidate.isEmpty else { continue }
                let range = NSRange(candidate.startIndex..<candidate.endIndex, in: candidate)
                for match in regex.matches(in: candidate, range: range) {
                    guard match.numberOfRanges >= 2,
                          let valueRange = Range(match.range(at: 1), in: candidate),
                          let value = Double(candidate[valueRange])
                    else {
                        continue
                    }
                    largestBillionCount = max(largestBillionCount, value)
                }
            }

            return largestBillionCount > 0 ? largestBillionCount * 1_000_000_000 : nil
        }
    }
}
