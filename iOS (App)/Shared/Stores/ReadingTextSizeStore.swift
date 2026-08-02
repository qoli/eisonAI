import Foundation

enum ReadingTextSizeOption: Double, CaseIterable, Identifiable {
    case compact = 0.85
    case standard = 1.0
    case large = 1.15
    case extraLarge = 1.3
    case accessibility = 1.5

    var id: Double { rawValue }

    var title: String {
        switch self {
        case .compact: "Compact"
        case .standard: "Standard"
        case .large: "Large"
        case .extraLarge: "Extra Large"
        case .accessibility: "Accessibility"
        }
    }
}

enum ReadingTextSizeStore {
    static func normalizedScale(_ value: Double) -> Double {
        ReadingTextSizeOption.allCases.min(by: {
            abs($0.rawValue - value) < abs($1.rawValue - value)
        })?.rawValue ?? ReadingTextSizeOption.standard.rawValue
    }
}
