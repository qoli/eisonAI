//
//  Loader.swift
//
//
//  Created by Jin Wang on 28/6/2024.
//

import Foundation

/// The object used to load the tiktoken file into an encoder object.
struct Loader {
    
    enum Error: Swift.Error {
        /// Throw when invalid format found in the tiktoken file. Each line should contain
        /// a base64 encoded byte sequence and an integer as its corresponding token/rank.
        case invalidFormat
        
        /// Throw when a byte sequence is not base64 encoded.
        case invalidEncoding
    }
    
    func load(fileURL: URL) async throws -> Encoder {
        var encoder = Encoder()
        
        for line in try fileURL.lines() {
            let splits = line.split(separator: " ")
            guard splits.count == 2 else {
                throw Error.invalidFormat
            }
            
            guard let data = Data(base64Encoded: String(splits[0])) else {
                throw Error.invalidEncoding
            }
            
            let token = Token(splits[1])
            encoder[data] = token
        }
        
        return encoder
    }
}

private extension URL {
    func lines() throws -> [String] {
        return try String(contentsOf: self, encoding: .utf8)
            .split(separator: "\n")
            .map { String($0) }
    }
}
