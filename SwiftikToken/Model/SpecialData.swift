//
//  SpecialData.swift
//
//
//  Created by Jin Wang on 4/7/2024.
//

import Foundation

enum SpecialData: String {
    /**
     * Represents the end of the text.
     */
    case endOfText = "<|endoftext|>"
    
    /**
     * Represents a prefix token.
     */
    case fimPrefix = "<|fim_prefix|>"
    
    /**
     * Represents a middle token.
     */
    case fimMiddle = "<|fim_middle|>"
    
    /**
     * Represents a suffix token.
     */
    case fimSuffix = "<|fim_suffix|>"
    
    /**
     * Represents the end of a prompt.
     */
    case endOfPrompt = "<|endofprompt|>"
}
