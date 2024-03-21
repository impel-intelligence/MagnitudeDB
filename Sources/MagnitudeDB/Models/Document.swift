//
//  File.swift
//  
//
//  Created by Taylor Lineman on 12/28/23.
//

import Foundation

public struct Document: Codable {
    let id: Int
    public let content: String
    public let embedding: [Float]
    public let collection: Int
    var cell: Int?
}
