//
//  File.swift
//  
//
//  Created by David Nadoba on 08.05.20.
//

import XCTest
import BinaryKit
import SwiftRTP
import RTPAVKit

final class H264PerformanceTests: XCTestCase {
    let maxDatagramSize = 1500
    let idrSize = 30 * 1000 * 1000
    func testData() throws {
        typealias DataType = Data
        var rtpSerialzer = RTPSerialzer(maxSizeOfPacket: maxDatagramSize, synchronisationSource: RTPSynchronizationSource(rawValue: 1))
        let h264Serialzer = H264.NALNonInterleavedPacketSerializer<DataType>(maxSizeOfNalu: rtpSerialzer.maxSizeOfPayload)
        
        let sample = try getTypicialCMSampleBuffer(idrSize: idrSize)
        measure {
            do {
                let nalus = sample.convertToH264NALUnits(dataType: DataType.self)
                let packets = try h264Serialzer.serialize(nalus, timestamp: 2, lastNALUsForGivenTimestamp: true)
                for packet in packets {
                    _ = try rtpSerialzer.serialze(packet)
                }
            } catch {
                XCTFail(error.localizedDescription)
            }
        }
    }
    func testDispatchData() throws {
        typealias DataType = DispatchData
        var rtpSerialzer = RTPSerialzer(maxSizeOfPacket: maxDatagramSize, synchronisationSource: RTPSynchronizationSource(rawValue: 1))
        let h264Serialzer = H264.NALNonInterleavedPacketSerializer<DataType>(maxSizeOfNalu: rtpSerialzer.maxSizeOfPayload)
        
        let sample = try getTypicialCMSampleBuffer(idrSize: idrSize)
        measure {
            do {
                let nalus = sample.convertToH264NALUnits(dataType: DataType.self)
                let packets = try h264Serialzer.serialize(nalus, timestamp: 2, lastNALUsForGivenTimestamp: true)
                for packet in packets {
                    _ = try rtpSerialzer.serialze(packet)
                }
            } catch {
                XCTFail(error.localizedDescription)
            }
        }
    }
    func testUInt8Array() throws {
        typealias DataType = [UInt8]
        var rtpSerialzer = RTPSerialzer(maxSizeOfPacket: maxDatagramSize, synchronisationSource: RTPSynchronizationSource(rawValue: 1))
        let h264Serialzer = H264.NALNonInterleavedPacketSerializer<DataType>(maxSizeOfNalu: rtpSerialzer.maxSizeOfPayload)
        
        let sample = try getTypicialCMSampleBuffer(idrSize: idrSize)
        measure {
            do {
                let nalus = sample.convertToH264NALUnits(dataType: DataType.self)
                let packets = try h264Serialzer.serialize(nalus, timestamp: 2, lastNALUsForGivenTimestamp: true)
                for packet in packets {
                    _ = try rtpSerialzer.serialze(packet)
                }
            } catch {
                XCTFail(error.localizedDescription)
            }
        }
    }
}
