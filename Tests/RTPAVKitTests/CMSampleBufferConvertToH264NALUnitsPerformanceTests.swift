import XCTest
import SwiftRTP
import RTPAVKit
import CoreMedia
import BinaryKit

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
    idrSize: Int = 1000 * 1000 //  1mb
) throws -> CMSampleBuffer {
    let sps = H264.NALUnit(
        header: .init(referenceIndex: 2, type: .sequenceParameterSet),
        payload: BinaryReader(hexString: "42c028da01e0089f97011000003e90000bb800f1832a")!.bytes)
    let pps = H264.NALUnit(
    header: .init(referenceIndex: 2, type: .pictureParameterSet),
    payload: BinaryReader(hexString: "ce3c80")!.bytes)
    let format = try CMFormatDescription(
        h264ParameterSets: [sps, pps].map{ Data($0.bytes) },
        nalUnitHeaderLength: 4
    )
    
    let idr = H264.NALUnit(
        header: .init(referenceIndex: 1, type: .instantaneousDecodingRefreshCodedSlice),
        payload: generateRandomBytes(size: idrSize, type: Data.self))
    return try idr.sampleBuffer(formatDescription: format, time: .zero)
}

final class CMSampleBufferConvertToH264NALUnitsPerformanceTests: XCTestCase {
    func testDispatchData() throws {
        typealias DataType = DispatchData
        let sample = try getTypicialCMSampleBuffer()
        measure {
            _ = sample.convertToH264NALUnits(dataType: DataType.self)
        }
    }
    func testData() throws {
        typealias DataType = Data
        let sample = try getTypicialCMSampleBuffer()
        measure {
            _ = sample.convertToH264NALUnits(dataType: DataType.self)
        }
    }
    func testUInt8Array() throws {
        typealias DataType = [UInt8]
        let sample = try getTypicialCMSampleBuffer()
        measure {
            _ = sample.convertToH264NALUnits(dataType: DataType.self)
        }
    }
}
