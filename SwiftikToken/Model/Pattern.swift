//
//  Pattern.swift
//
//
//  Created by Jin Wang on 4/7/2024.
//

import Foundation

/// A collection of regex patterns used to abstract/identify byte sequences that can be encoded.
enum Pattern: String {
    case p50k = #"'s|'t|'re|'ve|'m|'ll|'d| ?[A-Za-z]+| ?[0-9]+| ?[^\sA-Za-z0-9]+|\s+(?!\S)|\s+"#
    case p100k = #"'s|'t|'re|'ve|'m|'ll|'d|[^\r\n\p{L}\p{N}]?\p{L}+|\p{N}{1,3}| ?[^\s\p{L}\p{N}]+[\r\n]*|\s*[\r\n]+|\s+(?!\S)|\s+"#
    case o200k = #"[^\r\n\p{L}\p{N}]?[\p{Lu}\p{Lt}\p{Lm}\p{Lo}\p{M}]*[\p{Ll}\p{Lm}\p{Lo}\p{M}]+(?i:'s|'t|'re|'ve|'m|'ll|'d)?|[^\r\n\p{L}\p{N}]?[\p{Lu}\p{Lt}\p{Lm}\p{Lo}\p{M}]+[\p{Ll}\p{Lm}\p{Lo}\p{M}]*(?i:'s|'t|'re|'ve|'m|'ll|'d)?|\p{N}{1,3}| ?[^\s\p{L}\p{N}]+[\r\n/]*|\s*[\r\n]+|\s+(?!\S)|\s+"#
    
    func makeRegex() throws -> Regex<AnyRegexOutput> {
        return switch self {
        case .p50k:
            try Regex(rawValue)
        case .p100k:
            try Regex(rawValue).ignoresCase()
        case .o200k:
            try Regex(rawValue).ignoresCase()
        }
    }
}
