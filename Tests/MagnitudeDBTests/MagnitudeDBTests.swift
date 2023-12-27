import XCTest
@testable import MagnitudeDB
import SLlama

fileprivate struct SavedEmbeddingsData: Codable {
    var content: String
    var embeddings: [Double]
}

final class MagnitudeDBTests: XCTestCase {
    var database: MagnitudeDB!
    
    override class func setUp() {
        print("Running Setup")
        var dbLocation = URL(fileURLWithPath: #file, isDirectory: false).deletingLastPathComponent()
        dbLocation = dbLocation.appendingPathComponent("Resources", conformingTo: .directory).appendingPathComponent("data.sql")
        try? FileManager.default.removeItem(at: dbLocation)

        let database = MagnitudeDB(dataURL: dbLocation)
        
        var outputDirectory = URL(fileURLWithPath: #file, isDirectory: false).deletingLastPathComponent()
        outputDirectory = outputDirectory.appendingPathComponent("Resources", conformingTo: .directory).appendingPathComponent("output", conformingTo: .directory)

        let files = try! FileManager.default.contentsOfDirectory(atPath: outputDirectory.path())
        
        for file in files {
            guard file != ".DS_Store" else { continue }
            do {
                let fileURL = outputDirectory.appending(path: file)
                let fileBlob = try Data(contentsOf: fileURL)
                let tmp = try JSONDecoder().decode(SavedEmbeddingsData.self, from: fileBlob)

                try database.addDocument(content: tmp.content, embedding: tmp.embeddings)
            } catch {
                print("(\(file)) Failed to retrieve:", error)
            }
        }
    }
    
    override func setUp() async throws {
        var dbLocation = URL(fileURLWithPath: #file, isDirectory: false).deletingLastPathComponent()
        dbLocation = dbLocation.appendingPathComponent("Resources", conformingTo: .directory).appendingPathComponent("data.sql")
        
        database = MagnitudeDB(dataURL: dbLocation)
    }
        
    func testReadData() async throws {
        let documents = try database.getAllDocuments()
        print("Found \(documents.count) documents")
    }
    
    func testDotProductSearch() async throws {
        let embedding = TestEmbeddings.searchText
        
        print("Dot Product Search")
        let _ = try database.dotProductSearch(query: embedding)
    }
    
    func testCosineSearch() async throws {
        let embedding = TestEmbeddings.searchText
        
        print("Cosine Search")
        let _ = try database.dotProductSearch(query: embedding)
    }
    
    func testEuclidianDistanceSearch() async throws {
        let embedding = TestEmbeddings.searchText
        
        print("Euclidian Distance Search")
        let _ = try database.euclidianDistanceSearch(query: embedding)
    }
    
    func testVoronoiSearch() async throws {
        let embedding = TestEmbeddings.searchText
        
        print("Training Database")
        try database.trainDatabase(targetCellCount: 64)
        
        print("Voronoi Search")
        let _ = try database.voronoiSearch(query: embedding)
    }
}
