//
//  File.swift
//  
//
//  Created by David Nadoba on 20.04.20.
//

import Foundation
import CoreMedia
import VideoToolbox
import SwiftRTP
import BinaryKit
import Network

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
            return KERN_SUCCESS
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

extension CVPixelBuffer {
    /// Returns the width of the PixelBuffer in pixels.
    var width: Int { CVPixelBufferGetWidth(self) }
    /// Returns the height of the PixelBuffer in pixels.
    var height: Int { CVPixelBufferGetHeight(self) }
}

public final class RTPH264Sender {
    private let queue: DispatchQueue
    private let collectionQueue: DispatchQueue = DispatchQueue(label: "de.nadoba.\(RTPH264Sender.self).data-transfer-report-collection")
    private var encoder: VideoEncoder?
    private let connection: NWConnection
    private var rtpSerialzer: RTPSerialzer = .init(maxSizeOfPacket: 9216, synchronisationSource: RTPSynchronizationSource(rawValue: .random(in: UInt32.min...UInt32.max)))
    private lazy var h264Serialzer: H264.NALNonInterleavedPacketSerializer<Data> = .init(maxSizeOfNalu: rtpSerialzer.maxSizeOfPayload)
    public var onCollectConnectionMetric: ((NWConnection.DataTransferReport) -> ())?
    public init(endpoint: NWEndpoint, targetQueue: DispatchQueue? = nil) {
        queue = DispatchQueue(label: "de.nadoba.\(RTPH264Sender.self)", target: targetQueue)
        connection = NWConnection(to: endpoint, using: .udp)
        connection.start(queue: queue)
    }
    
    @discardableResult
    public func setupEncoderIfNeeded(width: Int, height: Int) -> VideoEncoder {
        if let encoder = self.encoder, encoder.width == width, encoder.height == height {
            return encoder
        }
        let encoderSpecification: NSDictionary = [
            kVTCompressionPropertyKey_AllowFrameReordering: false,
            kVTCompressionPropertyKey_RealTime: true,
            kVTCompressionPropertyKey_MaximizePowerEfficiency: true,
        ]
        
        #if os(macOS)
        encoderSpecification.setValue(true, forKey: kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder as String)
        #endif
        
        let encoder = try! VideoEncoder(
            width: width,
            height: height,
            codec: .h264,
            encoderSpecification: [
                kVTCompressionPropertyKey_AllowFrameReordering: false,
                //kVTCompressionPropertyKey_MaxFrameDelayCount: 0, // did not work.  would still delay frames and reorder them
                kVTCompressionPropertyKey_RealTime: true,
            ],
            imageBufferAttributes: nil)
        
        encoder.callback = { [weak self] buffer, flags in
            self?.sendBuffer(buffer)
        }
        
        self.encoder = encoder
        return encoder
    }
    
    var frameCount: Int = 0
    
    public func encodeAndSendFrame(_ frame: CVPixelBuffer, presentationTimeStamp: CMTime, frameDuration: CMTime) {
        frameCount += 1
        do {
            let encoder = setupEncoderIfNeeded(width: frame.width, height: frame.height)
            try encoder.encodeFrame(imageBuffer: frame, presentationTimeStamp: presentationTimeStamp, duration: frameDuration, frameProperties: [
                kVTEncodeFrameOptionKey_ForceKeyFrame: frameCount.isMultiple(of: 60),
            ])
            //encoder.finishEncoding(untilPresenetationTimeStamp: presentationTimeStamp)
        } catch {
            print(error, #file, #line)
        }
    }
    var firstTimestampValue: Int64?
    func getTimestampValueOffset(for timestampValue: Int64) -> Int64 {
        guard let firstTimestampValue = firstTimestampValue else {
            self.firstTimestampValue = timestampValue
            return timestampValue
        }
        return firstTimestampValue
    }
    private func sendBuffer(_ sampleBuffer: CMSampleBuffer) {
        let nalus = sampleBuffer.convertToH264NALUnitsAndAddPPSAndSPSIfNeeded(dataType: Data.self)
        let timestampValue = sampleBuffer.presentationTimeStamp.convertScale(90_000, method: .default).value
        let timestamp = UInt32(timestampValue - getTimestampValueOffset(for: timestampValue))
        sendNalus(nalus, timestamp: timestamp)
    }
    var dataTransferReportCollectionInterval: TimeInterval = 1
    var currentDataTransferReportStartTime: TimeInterval?
    var currentDataTransferReport: NWConnection.PendingDataTransferReport?
    private func now() -> TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }
    private func shouldStartNewDataTransferReportReport() -> Bool {
        guard let currentDataTransferReportStartTime = currentDataTransferReportStartTime else { return true }
        let elapsedSeconds = now() - currentDataTransferReportStartTime
        return elapsedSeconds > dataTransferReportCollectionInterval
    }
    private func startAndCollectDataTransferReportIfNeeded() {
        guard let onCollectConnectionMetric = onCollectConnectionMetric else { return }
        guard shouldStartNewDataTransferReportReport() else { return }
        let newDataTransferReport = connection.startDataTransferReport()
        currentDataTransferReport?.collect(queue: collectionQueue, completion: { report in
            onCollectConnectionMetric(report)
        })
        currentDataTransferReport = newDataTransferReport
        currentDataTransferReportStartTime = now()
    }
    private func sendNalus(_ nalus: [H264.NALUnit<Data>], timestamp: UInt32) {
        guard connection.maximumDatagramSize > 0 else { return }
        rtpSerialzer.maxSizeOfPacket = min(9216, connection.maximumDatagramSize)
        h264Serialzer.maxSizeOfNaluPacket = rtpSerialzer.maxSizeOfPayload
        
        startAndCollectDataTransferReportIfNeeded()
        
        do {
            let packets = try h264Serialzer.serialize(nalus, timestamp: timestamp, lastNALUsForGivenTimestamp: true)
            connection.batch {
                for packet in packets {
                    do {
                        let data: Data = try rtpSerialzer.serialze(packet)
                        connection.send(content: data, completion: .idempotent)
                    } catch {
                        print(error, #file, #line)
                    }
                }
            }
        } catch {
            print(error, #file, #line)
        }
    }
}
