//
//  Token.swift
//
//
//  Created by Jin Wang on 4/7/2024.
//

import Foundation

/// A token is the encoding of a byte sequence. In the tiktoken mapping file, each
/// byte sequence on the left is mapped to a token. This mapping file allows us to encode and
/// decode a sequence of byte. In most cases, the token is also known as the rank of the byte sequence
/// in the byte pair encoding algorithm.
public typealias Token = Int

extension Token {
    /// The default token/rank for any unknown byte sequences.
    static let unknown = 0
}
