//
//  File.swift
//  
//
//  Created by Taylor Lineman on 12/28/23.
//

import Foundation

public struct Document: Codable {
    let id: Int
    let content: String
    let embedding: [Double]
    let collection: Int
    var cell: Int?
}
