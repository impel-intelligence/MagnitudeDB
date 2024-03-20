import XCTest
import SwiftCSV
@testable import MagnitudeDB

final class MagnitudeDBTests: XCTestCase {
    
    override class func setUp() {
        load()
    }
    
    override func setUp() async throws {
        load()
    }
    
    private func load() {
        /*
         Load CSV
         Vector Dimensions: 1536
         Format:
         id,url,title,text,title_vector,content_vector,vector_id
         */
    }
    
    func testLoadDatabase() throws {
        let baseLocation = URL(fileURLWithPath: #file, isDirectory: false).deletingLastPathComponent()
        let dbLocation = baseLocation.appendingPathComponent("Resources", conformingTo: .directory)
        
        if FileManager.default.fileExists(atPath: dbLocation.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: dbLocation)
        }

        let csvLocation = baseLocation.appendingPathComponent("Resources", conformingTo: .directory).appendingPathComponent("xaa")

        let csv = try EnumeratedCSV(url: csvLocation, loadColumns: false)
        
        let database = try MagnitudeDatabase(vectorDimensions: 1534, dataURL: dbLocation)
                
        let collection = try database.createCollection("xaa")
        
        for item in csv.rows {
            let content = item[3]
            let vectorString = item[5]
            let vector = vectorString.split(separator: ",").compactMap({
                return Float($0.trimmingCharacters(in: .whitespaces))
            })
            
            guard !vector.isEmpty else { break }
            try database.createDocument(collection: collection, content: content, embedding: vector)
        }
        
        let results = try database.search(query: TestEmbeddings.marchTitle, amount: 2)
        print(results.map({$0.content}))
    }
}
