import XCTest
@testable import MagnitudeDB

fileprivate struct SavedEmbeddingsData: Codable {
    var content: String
    var embeddings: [Double]
}

final class MagnitudeDBTests: XCTestCase {
    var database: MagnitudeDB!
    
    override class func setUp() {
        print("Running Setup")
        let baseLocation = URL(fileURLWithPath: #file, isDirectory: false).deletingLastPathComponent()
        let dbLocation = baseLocation.appendingPathComponent("Resources", conformingTo: .directory).appendingPathComponent("data.sql")
        let metaLocation = baseLocation.appendingPathComponent("Resources", conformingTo: .directory).appendingPathComponent("meta.json")

//        try? FileManager.default.removeItem(at: dbLocation)

        let database = MagnitudeDB(dataURL: dbLocation, metaURL: metaLocation)

//        var outputDirectory = URL(fileURLWithPath: #file, isDirectory: false).deletingLastPathComponent()
//        outputDirectory = outputDirectory.appendingPathComponent("Resources", conformingTo: .directory).appendingPathComponent("output", conformingTo: .directory)
//
//        do {
//            let files = try FileManager.default.contentsOfDirectory(atPath: outputDirectory.path())
//            let collection = try database.createCollection("wikipedia")
//            
//            for file in files {
//                guard file != ".DS_Store" else { continue }
//                do {
//                    let fileURL = outputDirectory.appending(path: file)
//                    let fileBlob = try Data(contentsOf: fileURL)
//                    let tmp = try JSONDecoder().decode(SavedEmbeddingsData.self, from: fileBlob)
//                    
//                    try database.createDocument(collection: collection, content: tmp.content, embedding: tmp.embeddings)
//                } catch {
//                    print("(\(file)) Failed to retrieve:", error)
//                }
//            }
//        } catch {
//            print("Failed to initialize database", error)
//        }
        
        do {
            print("Reset Database")
            try database.resetTraining()
            print("Training Database")
            try database.train(targetCellCount: 64)
        } catch {
            print("Failed to train database")
        }
    }
    
    override func setUp() async throws {
        let baseLocation = URL(fileURLWithPath: #file, isDirectory: false).deletingLastPathComponent()
        let dbLocation = baseLocation.appendingPathComponent("Resources", conformingTo: .directory).appendingPathComponent("data.sql")
        let metaLocation = baseLocation.appendingPathComponent("Resources", conformingTo: .directory).appendingPathComponent("meta.json")

        database = MagnitudeDB(dataURL: dbLocation, metaURL: metaLocation)
    }
        
//    func testReadWikipediaCollection() async throws {
//        let collection = try database.getCollection("wikipedia")
//        let documents = try database.getAllDocuments(in: collection)
//        XCTAssert(documents.count == 4857)
//    }
//    
//    func testReadEmptyCollection() async throws {
//        let collection = try database.createCollection("woah")
//        let documents = try database.getAllDocuments(in: collection)
//        XCTAssert(documents.count == 0)
//    }
    
//    func testDotProductSearch() async throws {
//        let collection = try database.getCollection("wikipedia")
//        let embedding = TestEmbeddings.searchText
//        
//        print("Dot Product Search")
//        let _ = try database.dotProductSearch(query: embedding, collection: collection)
//    }
//    
//    func testCosineSearch() async throws {
//        let collection = try database.getCollection("wikipedia")
//        let embedding = TestEmbeddings.searchText
//        
//        print("Cosine Search")
//        let _ = try database.dotProductSearch(query: embedding, collection: collection)
//    }
//    
//    func testEuclidianDistanceSearch() async throws {
//        let collection = try database.getCollection("wikipedia")
//        let embedding = TestEmbeddings.searchText
//        
//        print("Euclidian Distance Search")
//        let _ = try database.euclidianDistanceSearch(query: embedding, collection: collection)
//    }
    
    func testVoronoiSearch() async throws {
        let collection = try database.getCollection("wikipedia")
        let embedding = TestEmbeddings.searchText
                
        print("Voronoi Search")
        let _ = try database.voronoiSearch(query: embedding, collection: collection)
    }
    
//    func testVoronoiSearchNoTraining() async throws {
//        let collection = try database.getCollection("wikipedia")
//        let embedding = TestEmbeddings.searchText
//
//        print("Reset Training")
//        try database.resetTraining()
//
//        print("Voronoi Search")
//        XCTAssertThrowsError(try database.voronoiSearch(query: embedding, collection: collection))
//    }
//
//    func testDeleteCollection() async throws {
//        let collection = try database.createCollection("This is so cool")
//        try database.deleteCollection(collection)
//        XCTAssertThrowsError(try database.getCollection("This is so cool"))
//    }
}
