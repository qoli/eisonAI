//
//  TokenEncoder.swift
//
//
//  Created by Jin Wang on 28/6/2024.
//

import Foundation

struct TokenEncoder {
    
    enum Error: Swift.Error {
        /// Throw when we found a special token in the input but its encoding is missing
        /// from the special token encoder.
        case specialTokenMissingFromEncoder
        
        /// Throw when we try to encode some part of the input text or a special token
        case encodingFailed
    }
    
    let encoder: Encoder
    let specialTokenEncoder: Encoder
    let regex: Regex<AnyRegexOutput>
    
    private let encoding = BytePairEncoding()
    
    init(
        encoder: Encoder,
        specialTokenEncoder: Encoder,
        regex: Regex<AnyRegexOutput>
    ) {
        self.encoder = encoder
        self.specialTokenEncoder = specialTokenEncoder
        self.regex = regex
    }
    
    func encode(
        _ text: String,
        allowedSpecialTokens: Set<String>
    ) throws -> [Token] {
        
        var encodedTokens = [Token]()
        var startIndex = text.startIndex
        
        while true {
            var slice = String(text[startIndex...])
            
            let nextSpecialMatch = allowedSpecialTokens.findMatch(in: slice)
            if let match = nextSpecialMatch {
                slice = String(slice[..<match.index])
            }
            
            let matches = slice.matches(of: regex)
            
            // Add encoded tokens
            for match in matches {
                let segment = slice[match.range]
                guard let piece = segment.data(using: .utf8) else {
                    throw Error.encodingFailed
                }
                
                if let token = encoder[piece] {
                    encodedTokens.append(token)
                } else {
                    let tokens = try encoding.encode(piece: piece, encoder: encoder)
                    encodedTokens.append(contentsOf: tokens)
                }
            }
            
            // Add special tokens and end looping if no special token
            if let match = nextSpecialMatch {
                let special = match.value
                guard let encoded = special.data(using: .utf8) else {
                    throw Error.encodingFailed
                }
                
                if let token = specialTokenEncoder[encoded] {
                    encodedTokens.append(token)
                } else {
                    throw Error.specialTokenMissingFromEncoder
                }
                
                startIndex = text.index(match.index, offsetBy: match.value.count)
            } else {
                break
            }
        }
        
        return encodedTokens
    }
}

private struct Match {
    let index: String.Index
    let value: String
}

private extension Collection where Element == String {
    func findMatch(in text: String) -> Match? {
        var minIndex = text.endIndex
        var value: String? = nil
        
        for element in self {
            if let index = text.range(of: element)?.lowerBound, 
                index < minIndex {
                minIndex = index
                value = element
            }
        }
        
        return value.flatMap { Match(index: minIndex, value: $0) }
    }
}
