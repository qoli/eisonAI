//
//  Tokenizer.swift
//
//
//  Created by Jin Wang on 2/7/2024.
//

import Foundation

struct Tokenizer {
    
    enum Error: Swift.Error {
        case disallowedSpecialTokenFound
    }
    
    let encoder: TokenEncoder
    let specialTokens: Set<String>
    
    func encode(
        text: String,
        allowedSpecial: Set<String>, 
        disallowedSpecial: Set<String>
    ) throws -> [Token] {
        let allowedSpecialSet = if allowedSpecial.count == 1, allowedSpecial.first == "all" {
            specialTokens
        } else {
            allowedSpecial
        }
        
        let disallowedSpecialSet = if disallowedSpecial.count == 1, disallowedSpecial.first == "all" {
            specialTokens.subtracting(allowedSpecialSet)
        } else {
            disallowedSpecial
        }
        
        if disallowedSpecialSet.contains(where: { text.contains($0) }) {
            throw Error.disallowedSpecialTokenFound
        }
        
        return try encoder.encode(
            text,
            allowedSpecialTokens: allowedSpecialSet
        )
    }
}
