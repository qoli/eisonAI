import XCTest
@testable import eisonAI

final class NumericFidelityValidatorTests: XCTestCase {
    func testAllowsNumbersCopiedFromSource() throws {
        try NumericFidelityValidator.validate(
            summary: "Revenue rose 12.5% to $2,400 in 2025.",
            source: "In 2025, revenue rose 12.5% and reached $2,400."
        )
    }

    func testRejectsInventedNumericFact() {
        XCTAssertThrowsError(
            try NumericFidelityValidator.validate(
                summary: "Revenue rose 18.5% in 2025.",
                source: "In 2025, revenue rose 12.5%."
            )
        ) { error in
            XCTAssertEqual(
                error as? NumericFidelityValidator.UnsupportedNumbersError,
                .init(values: ["18.5%"])
            )
        }
    }

    func testIgnoresOrdinarySingleDigitListMarkers() throws {
        try NumericFidelityValidator.validate(
            summary: "1. First point\n2. Second point",
            source: "First point. Second point."
        )
    }
}
