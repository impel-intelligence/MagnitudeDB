//
//  File.swift
//  
//
//  Created by Taylor Lineman on 12/28/23.
//

import Foundation
import SQLite

extension Array: Expressible where Element == Double { }

extension Array: Value where Element == Double {
    public typealias Datatype = Blob
    
    public static var declaredDatatype: String {
        return Blob.declaredDatatype
    }
    
    public static func fromDatatypeValue(_ blob: Blob) -> Array<Double> {
        let vectorData = try? JSONDecoder().decode(Self.self, from: Data.fromDatatypeValue(blob))
        return vectorData ?? []
    }
    
    public var datatypeValue: SQLite.Blob {
        let vectorData = try! JSONEncoder().encode(self)
        return vectorData.datatypeValue
    }
}
