import Foundation
import SQLite
import Accelerate

public final class MagnitudeDB {    
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
            let collections = Table("collections")
            let collectionsID = Expression<Int>("id")
            let collectionsName = Expression<String>("name")

            try db.run(collections.create(ifNotExists: true) { t in
                t.column(collectionsID, primaryKey: .autoincrement)
                t.column(collectionsName, unique: true)
            })
            
            // MARK: Create the documents table
            let documents = Table("documents")
            let documentID = Expression<Int>("id")
            let content = Expression<String>("content")
            let embedding = Expression<[Double]>("embedding")
            let cell = Expression<Int?>("cell")
            let collection = Expression<Int>("collection")
            
            try db.run(documents.create(ifNotExists: true) { t in
                t.column(documentID, primaryKey: .autoincrement)
                t.column(content)
                t.column(embedding)
                t.column(cell, references: cells, cellID)
                t.column(collection, references: collections, collectionsID)
            })
        } catch {
            print("Failed to create tables:", error)
        }
    }
            
    /// Implements a Pairwise Nearest Neighbor (PNN) method to generate a set of mean vectors used as Voronoi cell centroids
    public func train(targetCellCount: Int) throws {
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
    
    public func resetTraining() throws {
        let cellsTable = Table("cells")

        let documentsTable = Table("documents")
        let documentCell = Expression<Int?>("cell")

        try db.run(cellsTable.delete())

        try db.run(documentsTable.update(documentCell <- nil))
        
        isTrained = false
    }
}

// MARK: Data Retrieval and Setters
extension MagnitudeDB {
    public func createDocument(collection: Collection, content: String, embedding: [Double]) throws {
        let documents = Table("documents")
        let documentID = Expression<Int>("id")
        
        let nextID = (try db.scalar(documents.select(documentID.max)) ?? 0) + 1
        var document = Document(id: nextID, content: content, embedding: embedding, collection: collection.id)
        
        if self.isTrained {
            let closestCell = try closestCell(to: embedding)
            document.cell = closestCell.id
        }
        
        try db.run(documents.insert(document))
    }
    
    public func createCollection(_ name: String) throws -> Collection {
        let collectionTable = Table("collections")
        let collectionsName = Expression<String>("name")
        let collectionsID = Expression<Int>("id")

        let rowID = try db.run(collectionTable.insert([collectionsName <- name]))
        let databaseQuery = collectionTable.filter(collectionsID == Int(rowID)).limit(1)
        let collections: [Collection] = try db.prepare(databaseQuery).map({ return try $0.decode() })
        
        guard let collection = collections.first else { throw MagnitudeDBError.failedToCreateCollection }
        return collection
    }
    
    public func getCollection(_ name: String) throws -> Collection {
        let collectionTable = Table("collections")
        let collectionsName = Expression<String>("name")
        let databaseQuery = collectionTable.filter(collectionsName == name).limit(1)
        let collections: [Collection] = try db.prepare(databaseQuery).map({ return try $0.decode() })
        
        guard let collection = collections.first else { throw MagnitudeDBError.collectionDoesNotExist }
        return collection
    }

    public func getAllDocuments(in collection: Collection) throws -> [Document] {
        let documentsTable = Table("documents")
        let documentCollection = Expression<Int>("collection")
        
        var databaseQuery = documentsTable
        
        if collection != .all {
            databaseQuery = databaseQuery.where(documentCollection == collection.id)
        }
        
        return try db.prepare(databaseQuery).map({ return try $0.decode() })
    }
    
    public func getAllCells() throws -> [Cell] {
        let cells = Table("cells")
        return try db.prepare(cells).map({ return try $0.decode() })
    }
}

// MARK: Search Functions
extension MagnitudeDB {
    public func dotProductSearch(query: [Double], collection: Collection, count: Int = 5) throws -> [Document] {
        let documents = try getAllDocuments(in: collection)
        return try _dotProductSearch(query: query, count: count, documents: documents)
    }
    
    public func cosineSimilaritySearch(query: [Double], collection: Collection, count: Int = 5) throws -> [Document] {
        let documents = try getAllDocuments(in: collection)
        return try _cosineSimilaritySearch(query: query, count: count, documents: documents)
    }
    
    public func euclidianDistanceSearch(query: [Double], collection: Collection, count: Int = 5) throws -> [Document] {
        let documents = try getAllDocuments(in: collection)
        return try _euclidianDistanceSearch(query: query, count: count, documents: documents)
    }
    
    public func voronoiSearch(query: [Double], collection: Collection, count: Int = 5) throws -> [Document] {
        guard isTrained else { throw MagnitudeDBError.databaseNotTrained }
        
        let closestCell = try closestCell(to: query)
        let documentsTable = Table("documents")
        let documentCell = Expression<Int?>("cell")
        let documentCollection = Expression<Int>("collection")
        
        var databaseQuery = documentsTable.filter(documentCell == closestCell.id)
        
        if collection != .all {
            databaseQuery = databaseQuery.where(documentCollection == collection.id)
        }
        
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

        guard let closestCell = closestCell.1 else { throw MagnitudeDBError.noCellsFound }
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
