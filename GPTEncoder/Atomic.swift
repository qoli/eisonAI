//
//  File.swift
//  
//
//  Created by Alfian Losari on 27/03/23.
//

import Foundation

/// Based on https://www.donnywals.com/why-your-atomic-property-wrapper-doesnt-work-for-collection-types/

public class AtomicDict<Key: Hashable, Value>: CustomDebugStringConvertible {
    private var dictStorage = [Key: Value]()
    
    private let queue = DispatchQueue(label: "com.swiftgptencoder.atomic", qos: .utility, attributes: .concurrent,
                                      autoreleaseFrequency: .inherit, target: .global())
    
    public init() {}
    
    public subscript(key: Key) -> Value? {
        get { queue.sync { dictStorage[key] }}
        set { queue.async(flags: .barrier) { [weak self] in self?.dictStorage[key] = newValue } }
    }
    
    public var debugDescription: String {
        return dictStorage.debugDescription
    }
}
