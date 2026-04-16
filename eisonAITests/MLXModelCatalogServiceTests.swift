import XCTest
@testable import eisonAI

final class MLXModelCatalogServiceTests: XCTestCase {
    func testDecodeModelsAcceptsArrayBaseModel() throws {
        let json = """
        [
          {
            "id": "mlx-community/RakutenAI-3.0-MLX-4bit",
            "cardData": {
              "pipeline_tag": "text-generation",
              "base_model": ["Rakuten/RakutenAI-3.0"]
            },
            "lastModified": "2026-04-12T17:55:26.000Z",
            "safetensors": {
              "parameters": {
                "U8": 100,
                "U32": 200,
                "F32": 10,
                "BF16": 5
              },
              "total": 12345
            }
          }
        ]
        """

        let service = MLXModelCatalogService()
        let models = try service.decodeModels(from: Data(json.utf8))

        XCTAssertEqual(models.count, 1)
        XCTAssertEqual(models[0].id, "mlx-community/RakutenAI-3.0-MLX-4bit")
        XCTAssertEqual(models[0].pipelineTag, "text-generation")
        XCTAssertEqual(models[0].baseModel, "Rakuten/RakutenAI-3.0")
        XCTAssertEqual(models[0].rawSafeTensorTotal, 12345)
        XCTAssertEqual(models[0].estimatedParameterCount, 1600, accuracy: 0.001)
    }

    func testDecodeModelAcceptsStringBaseModelAndDateWithoutFractionalSeconds() throws {
        let json = """
        {
          "id": "mlx-community/Test-Model",
          "pipeline_tag": "image-text-to-text",
          "cardData": {
            "base_model": "org/Test-Base",
            "pipeline_tag": "image-text-to-text"
          },
          "lastModified": "2026-04-12T17:55:26Z",
          "safetensors": {
            "parameters": {
              "BF16": 42
            },
            "total": 6789
          }
        }
        """

        let service = MLXModelCatalogService()
        let model = try service.decodeModel(from: Data(json.utf8))

        XCTAssertEqual(model.id, "mlx-community/Test-Model")
        XCTAssertEqual(model.pipelineTag, "image-text-to-text")
        XCTAssertEqual(model.baseModel, "org/Test-Base")
        XCTAssertNotNil(model.lastModified)
        XCTAssertEqual(model.estimatedParameterCount, 42, accuracy: 0.001)
    }

    func testNamedModelSizeWinsOverAuxiliaryTensorCounts() throws {
        let json = """
        {
          "id": "mlx-community/gemma-4-26b-a4b-it-5bit",
          "cardData": {
            "base_model": "google/gemma-4-26b-a4b-it",
            "pipeline_tag": "image-text-to-text"
          },
          "lastModified": "2026-04-12T17:55:26.000Z",
          "safetensors": {
            "parameters": {
              "BF16": 1358865998,
              "U32": 3994270720
            },
            "total": 5353136718
          }
        }
        """

        let service = MLXModelCatalogService()
        let model = try service.decodeModel(from: Data(json.utf8))

        XCTAssertEqual(model.estimatedParameterCount, 26_000_000_000, accuracy: 0.001)
    }

    func testRecommendationScalesBeyond18GiB() {
        let model = MLXCatalogModel(
            id: "mlx-community/gemma-4-26b-a4b-it-5bit",
            pipelineTag: "image-text-to-text",
            baseModel: "google/gemma-4-26b-a4b-it",
            lastModified: nil,
            estimatedParameterCount: 33_313_031_758,
            rawSafeTensorTotal: 5_353_136_718
        )

        XCTAssertEqual(model.recommendation(forRAMGiB: 18), .caution)
        XCTAssertEqual(model.recommendation(forRAMGiB: 32), .recommended)
        XCTAssertEqual(model.recommendation(forRAMGiB: 128), .recommended)
    }
}
