//
//  BytePairEncoding.swift
//
//
//  Created by Jin Wang on 3/7/2024.
//

import Foundation

/// Object handles byte pair encoding algorithm.
struct BytePairEncoding {
    
    enum Error: Swift.Error {
        /// Throw when the input byte sequence is empty
        case emptyPiece
    }
    
    private struct Part {
        let index: Data.Index
        var token: Token?
    }
    
    /// Encode a piece of byte sequence into tokens based on the encoder.
    func encode(piece: Data, encoder: Encoder) throws -> [Token] {
        guard piece.count > 0 else {
            throw Error.emptyPiece
        }
        
        guard piece.count > 1 else {
            // No merge rules needed when there is only one byte.
            // We either return an mapped token or unknown.
            return [encoder[piece] ?? .unknown]
        }
        
        // Divide the byte sequence into parts and merge parts based on the encoder.
        var parts = [Part]()
        
        for i in 0..<piece.count + 1 {
            parts.append(Part(index: i, token: nil))
        }
        
        // Initialise parts by merging each neighbour bytes.
        for i in 0..<parts.count - 2 {
            parts[i] = Part(
                index: i,
                token: token(
                    for: piece,
                    encoder: encoder,
                    parts: parts,
                    startIndex: i,
                    skip: 0
                )
            )
        }
        
        // Every loop, we identify the minimum rank/token of all parts based on the encoder.
        // We then merge the next part into the min part and remove the next part from the array.
        // We keep going until there is only one part left or if all parts are mapped to unknown tokens.
        while parts.count > 1 {
            guard let minIndex = indexOfMinToken(parts: parts) else { break }
            
            parts[minIndex].token = token(
                for: piece,
                encoder: encoder,
                parts: parts, 
                startIndex: minIndex,
                skip: 1
            )
            
            if minIndex > 0 {
                let prevIndex = minIndex - 1
                parts[prevIndex].token = token(
                    for: piece,
                    encoder: encoder,
                    parts: parts,
                    startIndex: prevIndex,
                    skip: 1
                )
            }
            
            parts.remove(at: minIndex + 1)
        }
        
        // For each remaining part, we calculate their token based on the encoder
        // and return the token sequence.
        var tokens = [Token]()
        for i in 0..<(parts.count - 1) {
            let range = parts[i].index..<parts[i + 1].index
            tokens.append(
                encoder[piece.subdata(in: range)] ?? .unknown
            )
        }
        return tokens
    }
    
    private func token(
        for piece: Data,
        encoder: Encoder,
        parts: [Part],
        startIndex: Int,
        skip: Int
    ) -> Token? {
        guard startIndex + skip + 2 < parts.count else { return nil }
        
        let data = piece.subdata(
            in: parts[startIndex].index..<parts[startIndex + skip + 2].index
        )
        return encoder[data]
    }
    
    private func indexOfMinToken(parts: [Part]) -> Int? {
        var minToken: Token? = nil
        var minIndex: Int? = nil
        
        for i in parts.indices {
            if let token = parts[i].token {
                if let min = minToken {
                    if token < min {
                        minToken = token
                        minIndex = i
                    }
                } else {
                    minToken = token
                    minIndex = i
                }
            }
        }
        
        return minIndex
    }
}
