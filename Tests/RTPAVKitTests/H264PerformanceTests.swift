import XCTest
import RTPAVKit
import CoreMedia

func generateRandomBytes<D: ReferenceInitalizeableData>(size: Int, type: D.Type = D.self) -> D {
    var d = Array<UInt8>(repeating: 0, count: size)
    d.withUnsafeMutableBytes { data in
        let intBuffer = data.bindMemory(to: Int.self)
        for i in intBuffer.indices {
            intBuffer[i] = i
        }
    }
    return D.init(copyBytes: d)
}

func getTypicialCMSampleBuffer(
    idrSize: Int = 3000 * 1000, // 3000 kb
) -> [H264.NALUnit<D>] {
    
}

final class RTPAVKitTests: XCTestCase {
    func test_1() {
        
        measure {
            
        }
    }
}
