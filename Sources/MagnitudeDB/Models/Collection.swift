//
//  File.swift
//  
//
//  Created by Taylor Lineman on 12/28/23.
//

import Foundation

public struct Collection: Codable, Equatable {
    let id: Int
    let name: String
    
    static let all: Collection = Collection(id: -1, name: "_all_all_all_")
}
