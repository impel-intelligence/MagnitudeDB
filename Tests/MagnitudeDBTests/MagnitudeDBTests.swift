import XCTest
import SwiftCSV
@testable import MagnitudeDB

final class MagnitudeDBTests: XCTestCase {
    
    override class func setUp() {
        do {
            try loadDB()
        } catch {
            XCTFail("Could not setup database \(error)")
        }
    }
    
    override func setUp() async throws {
        try MagnitudeDBTests.loadDB()
    }
    
    private static func loadDB() throws {
        let baseLocation = URL(fileURLWithPath: #file, isDirectory: false).deletingLastPathComponent()
        let dbLocation = baseLocation.appendingPathComponent("Resources", conformingTo: .directory)
        
        let database = try MagnitudeDatabase(vectorDimensions: 1534, dataURL: dbLocation)
                
        if (try? database.getCollection("all")) == nil {
            let csvLocation = baseLocation.appendingPathComponent("Resources", conformingTo: .directory).appendingPathComponent("vector_database_wikipedia_articles_embedded.csv")

            // There is no data loaded so we need to load it all. This takes a WHILE so be careful.
            let collection = try database.createCollection("all")
            let csv = try EnumeratedCSV(url: csvLocation, delimiter: .comma, loadColumns: false)

            for item in csv.rows {
                let content = item[3]
                let vectorString = item[5]
                let vector = vectorString.split(separator: ",").compactMap({
                    return Float($0.trimmingCharacters(in: .whitespaces))
                })
                
                guard !vector.isEmpty else { break }
                try database.createDocument(collection: collection, content: content, embedding: vector)
            }
        }
    }
    
    func testLoadDatabase() throws {
        let baseLocation = URL(fileURLWithPath: #file, isDirectory: false).deletingLastPathComponent()
        let dbLocation = baseLocation.appendingPathComponent("Resources", conformingTo: .directory)
        
        let database = try MagnitudeDatabase(vectorDimensions: 1534, dataURL: dbLocation)
                
        if (try? database.getCollection("all")) == nil {
            let csvLocation = baseLocation.appendingPathComponent("Resources", conformingTo: .directory).appendingPathComponent("vector_database_wikipedia_articles_embedded.csv")

            // There is no data loaded so we need to load it all. This takes a WHILE so be careful.
            let collection = try database.createCollection("all")
            let csv = try EnumeratedCSV(url: csvLocation, delimiter: .comma, loadColumns: false)

            for item in csv.rows {
                let content = item[3]
                let vectorString = item[5]
                let vector = vectorString.split(separator: ",").compactMap({
                    return Float($0.trimmingCharacters(in: .whitespaces))
                })
                
                guard !vector.isEmpty else { break }
                try database.createDocument(collection: collection, content: content, embedding: vector)
            }
        }
        
        let results = try database.search(query: TestEmbeddings.marchTitle, amount: 2)
        XCTAssert(results.count == 2)
    }
    
    // TODO: Add performance testing
}
