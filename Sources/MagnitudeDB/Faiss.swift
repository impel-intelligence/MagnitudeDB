import Foundation
import SwiftFaiss

// FAISS may use different integer sizes on different devices.
typealias fInt = Int32

public class MagnitudeFAISSDB {
    var index: faiss.IndexBinaryHNSW
    
    init(vectorDimensions: fInt, numberOfNeighbors: fInt) {
        
    }
    
    func addVector(embedding: [Float]) {
        
    }
    
    func test() {
        
    }
}
