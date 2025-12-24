//
//  Encoder.swift
//
//
//  Created by Jin Wang on 4/7/2024.
//

import Foundation

/// A encoder is simply a map between a byte sequence and its token/rank.
/// It's essentially what the tiktoken file provides us with.
typealias Encoder = [Data: Token]

extension Encoder {
    
    enum Error: Swift.Error {
        /// Throw when string key cannot be encoded.
        case invalidKey
    }
    
    init(raw: [SpecialData: Token]) {
        var map = [Data: Token]()
        for (key, value) in raw {
            if let data = key.rawValue.data(using: .utf8) {
                map[data] = value
            }
        }
        self = map
    }
}
