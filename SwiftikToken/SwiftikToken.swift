import Foundation

private extension Bundle {
    // Provides a bundle similar to SwiftPM's Bundle.module, but works in app/framework targets too.
    static var swiftikModule: Bundle {
        #if SWIFT_PACKAGE
        return .module
        #else
        // Try to find the bundle where the resources are located.
        // 1) If this code is in a framework, use the bundle for this type.
        let bundleForType = Bundle(for: _BundleMarker.self)
        if bundleForType != Bundle.main {
            return bundleForType
        }
        // 2) If running inside an app, try the main bundle first.
        if let resourceBundleURL = Bundle.main.url(forResource: "SwiftikToken", withExtension: "bundle"),
           let resourceBundle = Bundle(url: resourceBundleURL) {
            return resourceBundle
        }
        return Bundle.main
        #endif
    }
}

// A private marker class to locate the correct framework bundle when not using SwiftPM.
private class _BundleMarker {}

public struct Tiktoken {
    
    enum Error: Swift.Error {
        case vocabularyFileNotFound
    }
    
    let encoding: Encoding
    private let loader = Loader()
    
    public init(encoding: Encoding) {
        self.encoding = encoding
    }
    
    public func encode(
        text: String,
        allowedSpecial: Set<String> = Set(),
        disallowedSpecial: Set<String> = Set(arrayLiteral: "all")
    ) async throws -> [Token] {
        guard let fileURL = Bundle.swiftikModule.url(
            forResource: encoding.rawValue,
            withExtension: "tiktoken"
        ) else {
            throw Error.vocabularyFileNotFound
        }
        
        let encoder = try await loader.load(fileURL: fileURL)
        let regex = try encoding.pattern.makeRegex()
        let tokenEncoder = TokenEncoder(
            encoder: encoder,
            specialTokenEncoder: encoding.specialTokenEncoder,
            regex: regex
        )
        
        return try Tokenizer(
            encoder: tokenEncoder,
            specialTokens: encoding.specialTokens
        ).encode(
            text: text,
            allowedSpecial: allowedSpecial,
            disallowedSpecial: disallowedSpecial
        )
    }
}

