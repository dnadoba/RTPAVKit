//
//  File.swift
//  
//
//  Created by David Nadoba on 27.05.20.
//

import XCTest
import SwiftRTP
import RTPAVKit
import AVFoundation
import VideoToolbox

final class MovieEncodeTests: XCTestCase {
    
    func testAllowFrameReordering() throws {
        let thisSourceFile = URL(fileURLWithPath: #file)
        let thisDirectory = thisSourceFile.deletingLastPathComponent()
        let resourceURL = thisDirectory.appendingPathComponent("test.mov")
        
        let asset = AVAsset(url: resourceURL)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderVideoCompositionOutput(
            videoTracks: asset.tracks(withMediaType: .video),
            videoSettings: nil
        )
        output.videoComposition = AVVideoComposition(propertiesOf: asset)
        
        let track = try XCTUnwrap(asset.tracks(withMediaType: .video).first)
        let size = track.naturalSize
        
        reader.add(output)
        
        XCTAssertTrue(reader.startReading())
        
        
        let encoder = try VideoEncoder(
            width: Int(size.width),
            height: Int(size.height),
            codec: .h264
        )
        encoder.allowFrameReordering = false
        
        var prevTimestamp: CMTime?
        
        encoder.callback = { sampleBuffer, flags in
            XCTAssertFalse(flags.contains(.frameDropped))
            let currentTimestamp = sampleBuffer.presentationTimeStamp
            XCTAssertTrue(currentTimestamp.isValid)
            defer { prevTimestamp = currentTimestamp }
            if let prevTimestamp = prevTimestamp {
                XCTAssertLessThan(prevTimestamp, currentTimestamp)
            }
        }
        var lastTimestamp: CMTime = .invalid
        while let sampleBuffer = output.copyNextSampleBuffer() {
            let presentationTimeStamp = sampleBuffer.presentationTimeStamp
            lastTimestamp = presentationTimeStamp
            let duration = sampleBuffer.duration
            
            let image = try XCTUnwrap(sampleBuffer.imageBuffer)
            try encoder.encodeFrame(imageBuffer: image, presentationTimeStamp: presentationTimeStamp, duration: duration)
        }
        
        encoder.finishEncoding(untilPresenetationTimeStamp: lastTimestamp)
        
    }
}

