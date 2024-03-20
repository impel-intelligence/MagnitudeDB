import Foundation
import SQLite
import SwiftFaiss
import SwiftFaissC
import SQLite_swift_extensions

public class MagnitudeDatabase {
    enum DBError: Error {
        case couldNotBuildDB
        case indexNotTrained
        case labelOutOfRange
    }
    
    enum IndexArea {
        case all
        case collection(collection: Collection)
    }
    
    class IndexPackage {
        let index: BaseIndex
        let documents: [Document]
        
        init(index: BaseIndex, documents: [Document]) {
            self.index = index
            self.documents = documents
        }
    }
    
    // Static
    private static let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    public static let defaultDataURL = documentsDirectory.appending(path: "magnitude")
    
    let dataURL: URL
    
    var databaseURL: URL {
        dataURL.appending(component: "data").appendingPathExtension(".sql")
    }
    
    var indexCache: URL {
        dataURL.appending(path: "index_cache").appending(component: "data").appendingPathExtension(".sql")
    }
    
    // Database
    @MainActor let db: Connection
    var vectorDimensions: Int
        
    init(vectorDimensions: Int, dataURL: URL = defaultDataURL, inMemory: Bool = false) throws {
        self.vectorDimensions = vectorDimensions
        self.dataURL = dataURL
        let databaseURL = dataURL.appending(component: "data").appendingPathExtension(".sql")
        
        do {
            if inMemory {
                self.db = try Connection(.temporary)
            } else {
                self.db = try Connection(databaseURL.path())
            }

            // Create the collections table
            let collections = Table("collections")
            let collectionsID = Expression<Int>("id")
            let collectionsName = Expression<String>("name")

            try db.run(collections.create(ifNotExists: true) { t in
                t.column(collectionsID, primaryKey: .autoincrement)
                t.column(collectionsName, unique: true)
            })
            
            // Create the documents table
            let documents = Table("documents")
            let documentID = Expression<Int>("id")
            let vectorID = Expression<Int>("vectorID")
            let content = Expression<String>("content")
            let embedding = Expression<[Float]>("embedding")
            let collection = Expression<Int>("collection")
            
            try db.run(documents.create(ifNotExists: true) { t in
                t.column(documentID, primaryKey: .autoincrement)
                t.column(vectorID)
                t.column(content)
                t.column(embedding)
                t.column(collection, references: collections, collectionsID)
            })
        } catch {
            throw DBError.couldNotBuildDB
        }
    }
}

// MARK: Index
extension MagnitudeDatabase {
    private func searchIndex(index: BaseIndex, query: [Float], amount: Int) throws -> [Int] {
        guard index.isTrained else {
            throw DBError.indexNotTrained
        }
        
        let result = try index.search([query], k: amount)
        
        return result.labels.flatMap({$0})
    }
    
    private func retrieveIndex(area: IndexArea) throws -> IndexPackage {
        switch area {
        case .all:
            return try retrieveIndexAll()
        case .collection(let collection):
            return try retrieveIndex(for: collection)
        }
    }
    
    private func retrieveIndexAll() throws -> IndexPackage {
        let indexURL = cacheURL(for: .all)
        let results = try getAllEmbeddings()

        if let cachedIndex = try? IVFFlatIndex.from(indexURL.path(percentEncoded: false)) {
            return IndexPackage(index: cachedIndex, documents: results.1)
        } else {
            let quantizer: FlatIndex = try FlatIndex(d: self.vectorDimensions, metricType: .l2)
            let index: IVFFlatIndex = try IVFFlatIndex(quantizer: quantizer, d: self.vectorDimensions, nlist: 2)
            
            try index.train(results.0)
            try index.add(results.0)
            
            // Cache the index so we do not need to reconstruct it in the future
            try index.saveToFile(indexURL.path(percentEncoded: false))
            
            return IndexPackage(index: index, documents: results.1)
        }
        
    }
    
    private func retrieveIndex(for collection: Collection) throws -> IndexPackage {
        let indexURL = cacheURL(for: .collection(collection: collection))
        let results = try getEmbeddings(for: collection)

        if let cachedIndex = try? IVFFlatIndex.from(indexURL.path(percentEncoded: false)) {
            return IndexPackage(index: cachedIndex, documents: results.1)
        } else {
            let quantizer: FlatIndex = try FlatIndex(d: self.vectorDimensions, metricType: .l2)
            let index: IVFFlatIndex = try IVFFlatIndex(quantizer: quantizer, d: self.vectorDimensions, nlist: 2)
            
            try index.train(results.0)
            try index.add(results.0)
            
            // Cache the index so we do not need to reconstruct it in the future
            try index.saveToFile(indexURL.path(percentEncoded: false))
            
            return IndexPackage(index: index, documents: results.1)
        }
    }
    
    private func invalidateCache(area: IndexArea) throws {
        switch area {
        case .all:
            let location = cacheURL(for: .all)
            try FileManager.default.removeItem(at: location)
        case .collection:
            let location = cacheURL(for: area)
            try FileManager.default.removeItem(at: location)
            
            // TODO: Optomize to edit the existing cache instead of deleting and then re-generating later
            // Because all collections are in the global index we need
            try self.invalidateCache(area: .all)
        }
    }
    
    private func cacheURL(for area: IndexArea) -> URL {
        switch area {
        case .all:
            return indexCache.appending(path: "all")
        case .collection(let collection):
            return indexCache.appending(path: "collection-\(collection.id)")
        }
    }
}

// MARK: Database
extension MagnitudeDatabase {
    public func createDocument(collection: Collection, content: String, embedding: [Float]) throws {
        let documents = Table("documents")
        let documentID = Expression<Int>("id")
        
        let nextID = (try db.scalar(documents.select(documentID.max)) ?? 0) + 1
        let document = Document(id: nextID, vectorID: 0, content: content, embedding: embedding, collection: collection.id)
        
        try db.run(documents.insert(document))
        try invalidateCache(area: .collection(collection: collection))
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
    
    public func deleteCollection(_ collection: Collection) throws {
        let collectionsID = Expression<Int>("id")
        let collection = Table("collections").filter(collectionsID == collection.id)

        try db.run(collection.delete())
    }
    
    public func getCollection(_ name: String) throws -> Collection {
        let collectionTable = Table("collections")
        let collectionsName = Expression<String>("name")
        let databaseQuery = collectionTable.filter(collectionsName == name).limit(1)
        let collections: [Collection] = try db.prepare(databaseQuery).map({ return try $0.decode() })
        
        guard let collection = collections.first else { throw MagnitudeDBError.collectionDoesNotExist }
        return collection
    }
    
    private func getAllEmbeddings() throws -> ([[Float]], [Document]) {
        let documentsTable = Table("documents")
        
        let documents: [Document] = try db.prepare(documentsTable).map({try $0.decode()})
        let vectors: [[Float]] = documents.map({$0.embedding})
        
        return (vectors, documents)
    }
    
    private func getEmbeddings(for collec: Collection) throws -> ([[Float]], [Document]) {
        let documentTable = Table("documents")
        let collection = Expression<Int>("collection")
        let databaseQuery = documentTable.filter(collection == collec.id)
        
        let documents: [Document] = try db.prepare(databaseQuery).map({try $0.decode()})
        let vectors: [[Float]] = documents.map({$0.embedding})
        
        return (vectors, documents)
    }
}

// MARK: Search
extension MagnitudeDatabase {
    public func search(query: [Float], amount: Int) throws -> [Document] {
        let indexPackage = try retrieveIndexAll()
        let labels = try self.searchIndex(index: indexPackage.index, query: query, amount: amount)
        let resultingDocuments = try translateLabels(labels: labels, documents: indexPackage.documents)
        
        return resultingDocuments
    }
    
    public func search(in collection: Collection, query: [Float], amount: Int) throws -> [Document] {
        let indexPackage = try retrieveIndexAll()
        let labels = try self.searchIndex(index: indexPackage.index, query: query, amount: amount)
        let resultingDocuments = try translateLabels(labels: labels, documents: indexPackage.documents)
        
        return resultingDocuments
    }
    
    private func translateLabels(labels: [Int], documents: [Document]) throws -> [Document] {
        var resultingDocuments: [Document] = []
        
        for index in labels where (index < documents.count && index >= 0) {
            resultingDocuments.append(documents[index])
        }

        return resultingDocuments
    }
}
