import XCTest
@testable import MagnitudeDB

final class MagnitudeDBTests: XCTestCase {
    override class func setUp() {
        load()
    }
    
    override func setUp() async throws {
        load()
    }
    
    private func load() {
//        let baseLocation = URL(fileURLWithPath: #file, isDirectory: false).deletingLastPathComponent()
//        let dbLocation = baseLocation.appendingPathComponent("Resources", conformingTo: .directory).appendingPathComponent("vector_database_wikipedia_articles_embedded.csv")
        /*
         Load CSV
         Vector Dimensions: 1536
         Format:
         id    url    title    text    content_vector
         */
    }
    
    func testFAISS() {
        let faiss = MagnitudeFAISSDB(vectorDimensions: 1536, numberOfNeighbors: 32)

         
    }
}
