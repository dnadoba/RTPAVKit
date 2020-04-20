//
//  File.swift
//  
//
//  Created by David Nadoba on 20.04.20.
//

import Foundation
import CoreMedia
import SwiftRTP
import BinaryKit

public extension CMSampleBuffer {
    @inlinable
    func convertToH264NALUnitsAndAddPPSAndSPSIfNeeded<D>(dataType: D.Type = D.self) -> [H264.NALUnit<D>] where D: MutableDataProtocol, D.Index == Int {
        var nalus = self.convertToH264NALUnits(dataType: D.self)
        if nalus.contains(where: { $0.header.type == H264.NALUnitType.instantaneousDecodingRefreshCodedSlice }),
            let formatDescription = self.formatDescription {
            let parameterSet = formatDescription.h264ParameterSets(dataType: D.self)
            nalus.insert(contentsOf: parameterSet, at: 0)
        }
        return nalus
    }
    @inlinable
    func convertToH264NALUnits<D>(dataType: D.Type = D.self) -> [H264.NALUnit<D>] where D: MutableDataProtocol, D.Index == Int {
        var nalus = [H264.NALUnit<D>]()
        CMSampleBufferCallBlockForEachSample(self) { (buffer, count) -> OSStatus in
            if let dataBuffer = buffer.dataBuffer, let formatDescription = formatDescription  {
                do {
                    let newNalus = try dataBuffer.withContiguousStorage { storage -> [H264.NALUnit<D>] in
                        let storage = storage.bindMemory(to: UInt8.self)
                        var reader = BinaryReader(bytes: storage)
                        var newNalus = [H264.NALUnit<D>]()
                        let nalUnitHeaderLength = formatDescription.nalUnitHeaderLength
                        while !reader.isEmpty {
                            let length = try reader.readInteger(byteCount: Int(nalUnitHeaderLength), type: UInt64.self)
                            let header = try H264.NALUnitHeader(from: &reader)
                            let payload = D(try reader.readBytes(Int(length) - 1))
                            newNalus.append(H264.NALUnit<D>(header: header, payload: payload))
                        }
                        return newNalus
                    }
                    nalus.append(contentsOf: newNalus)
                } catch {
                    print(error, #file, #line)
                }
            }
            return kOSReturnSuccess
        }
        return nalus
    }
}

public extension CMFormatDescription {
    @inlinable
    var nalUnitHeaderLength: Int32 {
        var nalUnitHeaderLength: Int32 = 0
        CMVideoFormatDescriptionGetH264ParameterSetAtIndex(self, parameterSetIndex: -1, parameterSetPointerOut: nil, parameterSetSizeOut: nil, parameterSetCountOut: nil, nalUnitHeaderLengthOut: &nalUnitHeaderLength)
        return nalUnitHeaderLength
    }
    @inlinable
    func h264ParameterSets<D>(dataType: D.Type = D.self) -> [H264.NALUnit<D>] where D: MutableDataProtocol, D.Index == Int {
        var nalus = [H264.NALUnit<D>]()
        var count = 0
        CMVideoFormatDescriptionGetH264ParameterSetAtIndex(self, parameterSetIndex: -1, parameterSetPointerOut: nil, parameterSetSizeOut: nil, parameterSetCountOut: &count, nalUnitHeaderLengthOut: nil)
        for index in 0..<count {
            do {
                var pointerOut: UnsafePointer<UInt8>?
                var size = 0
                CMVideoFormatDescriptionGetH264ParameterSetAtIndex(self, parameterSetIndex: index, parameterSetPointerOut: &pointerOut, parameterSetSizeOut: &size, parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil)
                if let pointerOut = pointerOut {
                    let data = UnsafeBufferPointer(start: pointerOut, count: size)
                    var reader = BinaryReader(bytes: data)
                    let nalu = H264.NALUnit(header: try .init(from: &reader), payload: D(try reader.readRemainingBytes()))
                    nalus.append(nalu)
                } else {
                    print("could not get H264ParameterSet")
                }
            } catch {
                print(error, #file, #line)
            }
        }
        return nalus
    }
}
