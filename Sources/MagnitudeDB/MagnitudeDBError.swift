//
//  File.swift
//  
//
//  Created by Taylor Lineman on 12/28/23.
//

import Foundation

enum MagnitudeDBError: LocalizedError {
    case failedToCreateCollection
    case collectionDoesNotExist
    case databaseNotTrained
    case noCellsFound
}
