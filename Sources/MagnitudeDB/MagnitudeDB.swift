import Foundation
import SQLite
import Accelerate

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

public final class MagnitudeDB {
    public struct Document: Codable {
        let id: Int
        let content: String
        let embedding: [Double]
        var cell: Int?
    }
    
    public struct Cell: Codable {
        let id: Int
        let point: [Double]
    }
    
    public static let defaultDataURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appending(path: "MagnitudeDB").appending(component: "db").appendingPathExtension("sql")
    
    let dataURL: URL
    
    @MainActor let db: Connection
    private var isTrained: Bool = false
    
    public init(dataURL: URL = defaultDataURL, inMemory: Bool = false) {
        self.dataURL = dataURL
        
        do {
            if inMemory {
                self.db = try! Connection(.temporary)
            } else {
                self.db = try Connection(dataURL.path())
            }
        } catch {
            self.db = try! Connection(.temporary)
        }
        
        do {
            // MARK: Create the cells table
            let cells = Table("cells")
            let cellID = Expression<Int>("id")
            let cellPoint = Expression<[Double]>("point")
            
            try db.run(cells.create(ifNotExists: true) { t in
                t.column(cellID, primaryKey: .autoincrement)
                t.column(cellPoint)
            })
            
            // MARK: Create the collections table
            //            let collections = Table("collections")
            //            let collections_id = Expression<Int>("id")
            //
            //            try db.run(collections.create(ifNotExists: true) { t in
            //                t.column(collections_id, primaryKey: .autoincrement)
            //            })
            
            // MARK: Create the documents table
            let documents = Table("documents")
            let documentID = Expression<Int>("id")
            let content = Expression<String>("content")
            let embedding = Expression<[Double]>("embedding")
            let cell = Expression<Int?>("cell")
            //            let collection = Expression<Int>("collection")
            
            try db.run(documents.create(ifNotExists: true) { t in
                t.column(documentID, primaryKey: .autoincrement)
                t.column(content)
                t.column(embedding)
                t.column(cell, references: cells, cellID)
                //                t.column(collection, references: collections, collections_id)
            })
        } catch {
            print("Failed to create tables:", error)
        }
    }
            
    /// Implements a Pairwise Nearest Neighbor (PNN) method to generate a set of mean vectors used as Voronoi cell centroids
    public func trainDatabase(targetCellCount: Int) throws {
        let cellsTable = Table("cells")
        let documentsTable = Table("documents")
        let allDocuments: [Document] = try db.prepare(documentsTable).map({ return try $0.decode() })
        
        let allVectors = allDocuments.map({$0.embedding})
        let reducedCells = recursiveCombination(allVectors: allVectors, targetCount: targetCellCount)
        
        var databaseCells: [Cell] = []
        for i in 0..<reducedCells.count {
            let cell = Cell(id: i, point: reducedCells[i])
            databaseCells.append(cell)
        }
        
        // Save the cells to the DB
        try db.run(cellsTable.insertMany(databaseCells))
        
        let cellColumn = Expression<Int?>("cell")
        let documentID = Expression<Int>("id")
        for document in allDocuments {
            var closestCell: (Double, Cell?) = (.greatestFiniteMagnitude, nil)
            
            for cell in databaseCells {
                var result: Double = 0
                vDSP_distancesqD(cell.point, 1, document.embedding, 1, &result, vDSP_Length(cell.point.count))
                
                if closestCell.0 > result {
                    closestCell = (result, cell)
                }
            }
            guard let closestCell = closestCell.1 else { continue }
            
            try db.run(documentsTable.filter(documentID == document.id).update(cellColumn <- closestCell.id))
        }
        
        isTrained = true
    }
}

// MARK: Data Retrieval and Setters
extension MagnitudeDB {
    public func addDocument(content: String, embedding: [Double]) throws {
        let documents = Table("documents")
        let documentID = Expression<Int>("id")
        
        let nextID = (try db.scalar(documents.select(documentID.max)) ?? 0) + 1
        var document = Document(id: nextID, content: content, embedding: embedding)
        
        if self.isTrained {
            let closestCell = try closestCell(to: embedding)
            document.cell = closestCell.id
        }
        
        try db.run(documents.insert(document))

    }
    
    public func getAllDocuments() throws -> [Document] {
        let documents = Table("documents")
        return try db.prepare(documents).map({ return try $0.decode() })
    }
    
    public func getAllCells() throws -> [Cell] {
        let cells = Table("cells")
        return try db.prepare(cells).map({ return try $0.decode() })
    }
}

// MARK: Search Functions
extension MagnitudeDB {
    func dotProductSearch(query: [Double], count: Int = 5) throws -> [Document] {
        let documents = try getAllDocuments()
        return try _dotProductSearch(query: query, count: count, documents: documents)
    }
    
    func cosineSimilaritySearch(query: [Double], count: Int = 5) throws -> [Document] {
        let documents = try getAllDocuments()
        return try _cosineSimilaritySearch(query: query, count: count, documents: documents)
    }
    
    func euclidianDistanceSearch(query: [Double], count: Int = 5) throws -> [Document] {
        let documents = try getAllDocuments()
        return try _euclidianDistanceSearch(query: query, count: count, documents: documents)
    }
    
    func voronoiSearch(query: [Double], count: Int = 5) throws -> [Document] {
        guard isTrained else { return [] } // TODO: Throw an error
        
        let closestCell = try closestCell(to: query)
        let documentsTable = Table("documents")
        let documentCell = Expression<Int?>("cell")
        let databaseQuery = documentsTable.filter(documentCell == closestCell.id)
        let cellDocuments: [Document] = try db.prepare(databaseQuery).map({ return try $0.decode() })

        return try _euclidianDistanceSearch(query: query, count: count, documents: cellDocuments)
    }
}

// MARK: Internal search functions
extension MagnitudeDB {
    private func _dotProductSearch(query: [Double], count: Int, documents: [Document]) throws -> [Document] {
        var candidates: [(score: Double, document: Document)] = []

        for document in documents {
            let result: Double = vDSP.distanceSquared(query, document.embedding)

            if !candidates.isEmpty {
                for i in 0..<candidates.count {
                    guard i < count else { break }
                    
                    if candidates[i].score < result {
                        candidates.insert((result, document), at: i)
                        break
                    }
                }
            } else if Double.leastNormalMagnitude < result {
                candidates.append((result, document))
            }
        }
        
        return candidates.prefix(count).map({$0.document})
    }
    
    private func _cosineSimilaritySearch(query: [Double], count: Int, documents: [Document]) throws -> [Document] {
        var candidates: [(score: Double, document: Document)] = []
        let queryMagnitude = sqrt(query.reduce(0) { $0 + $1 * $1 })
                
        for document in documents {
            var result: Double = vDSP.dot(query, document.embedding)
            let documentMagnitude = sqrt(document.embedding.reduce(0) { $0 + $1 * $1 })
            result /= (queryMagnitude * documentMagnitude)

            if !candidates.isEmpty {
                for i in 0..<candidates.count {
                    guard i < count else { break }
                    
                    if candidates[i].score < result {
                        candidates.insert((result, document), at: i)
                        break
                    }
                }
            } else if Double.leastNormalMagnitude < result {
                candidates.append((result, document))
            }
        }
        
        return candidates.prefix(count).map({$0.document})
    }
    
    private func _euclidianDistanceSearch(query: [Double], count: Int, documents: [Document]) throws -> [Document] {
        var candidates: [(score: Double, document: Document)] = []
        
        for document in documents {
            let result: Double = vDSP.distanceSquared(query, document.embedding)
            
            if !candidates.isEmpty {
                for i in 0..<candidates.count {
                    guard i < count else { break }
                    
                    if candidates[i].score > result {
                        candidates.insert((result, document), at: i)
                        break
                    }
                }
            } else if Double.greatestFiniteMagnitude > result {
                candidates.append((result, document))
            }
        }
        
        return candidates.prefix(count).map({$0.document})
    }
    
    private func closestCell(to vector: [Double]) throws -> Cell {
        let databaseCells: [Cell] = try self.getAllCells()

        var closestCell: (Double, Cell?) = (.greatestFiniteMagnitude, nil)
        
        for cell in databaseCells {
            var result: Double = 0
            vDSP_distancesqD(cell.point, 1, vector, 1, &result, vDSP_Length(cell.point.count))
            
            if closestCell.0 > result {
                closestCell = (result, cell)
            }
        }

        guard let closestCell = closestCell.1 else { return Cell(id: 0, point: []) } // TODO: Throw an error
        return closestCell
    }
}

// MARK: Helper Functions
extension MagnitudeDB {
    private func recursiveCombination(allVectors: [[Double]], targetCount: Int) -> [[Double]] {
        var mutableVectors = allVectors
        var vectorPairs: [([Double], [Double])] = []
        
        if mutableVectors.count % 2 != 0 {
            mutableVectors.removeLast() // Drop the last vector to make the array an even number. Necessary for repetitive pairing
        }
        
        while mutableVectors.count > 0 {
            guard let first = mutableVectors.first else { break }
            mutableVectors = [[Double]](mutableVectors.dropFirst())
            let nearestNeighborResults = findNearestNeighbor(vector: first, neighbors: mutableVectors)
            mutableVectors.remove(at: nearestNeighborResults.1)
            vectorPairs.append((first, nearestNeighborResults.0))
        }
        
        var resultVectors: [[Double]] = []
        for pair in vectorPairs {
            var result = [Double](repeating: 0.0, count: pair.0.count)
            vDSP_vasmD(pair.0, 1, pair.1, 1, [0.5], &result, 1, vDSP_Length(pair.0.count))
            resultVectors.append(result)
        }
        
        if resultVectors.count > targetCount {
            resultVectors = recursiveCombination(allVectors: resultVectors, targetCount: targetCount)
        }
        
        return resultVectors
    }
    
    private func findNearestNeighbor(vector: [Double], neighbors: [[Double]]) -> ([Double], Int) {
        var closestDistance: Double = .greatestFiniteMagnitude
        var closestVectorIndex: Int = 0
        
        for i in 0..<neighbors.count {
            let distance = vDSP.distanceSquared(vector, neighbors[i])
            
            if distance < closestDistance {
                closestVectorIndex = i
                closestDistance = distance
            }
        }
        
        return (neighbors[closestVectorIndex], closestVectorIndex)
    }

}
