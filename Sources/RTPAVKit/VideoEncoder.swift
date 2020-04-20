import Foundation
import VideoToolbox

public enum VideoCodec {
    case h264
    case h265
    case h265WithAlpha
}

public extension VideoCodec {
    var codecType: CMVideoCodecType {
        switch self {
        case .h264: return kCMVideoCodecType_H264
        case .h265: return kCMVideoCodecType_HEVC
        case .h265WithAlpha: return kCMVideoCodecType_HEVCWithAlpha
        }
    }
}

public final class VideoEncoder {
    public typealias Callback = (CMSampleBuffer, VTEncodeInfoFlags) -> ()
    public var callback: Callback?
    private var session: VTCompressionSession!
    public let width: Int
    public let height: Int
    public let codec: VideoCodec
    public init(
        allocator: CFAllocator? = nil,
        width: Int,
        height: Int,
        codec: VideoCodec,
        encoderSpecification: NSDictionary?,
        imageBufferAttributes: NSDictionary?,
        compressedDataAllocator: CFAllocator? = nil
    ) throws {
        self.width = width
        self.height = height
        self.codec = codec
        let ptr = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        var session: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: allocator,
            width: Int32.init(clamping: width),
            height: Int32.init(clamping: height),
            codecType: codec.codecType,
            encoderSpecification: encoderSpecification,
            imageBufferAttributes: imageBufferAttributes,
            compressedDataAllocator: compressedDataAllocator,
            outputCallback: { (selfPointer, _, status, infoFlags, sampleBuffer) in
                let mySelf = Unmanaged<VideoEncoder>.fromOpaque(UnsafeRawPointer(selfPointer!)).takeUnretainedValue()
                guard status == kOSReturnSuccess, let sampleBuffer = sampleBuffer else {
                    print(OSStatusError(status, description: "failed to compress frame"))
                    return
                }
                
                mySelf.callback?(sampleBuffer, infoFlags)
                
        }, refcon: ptr, compressionSessionOut: &session)
        
        guard status == kOSReturnSuccess, let unwrapedSession = session else {
            throw OSStatusError(status, description: "failed to create \(VTCompressionSession.self) width: \(width) height: \(height) codec: \(codec) encoderSpecification: \(encoderSpecification as Any) imageBufferAttributes: \(imageBufferAttributes as Any)")
        }
        self.session = unwrapedSession
    }
    deinit {
        if let session = session {
            VTCompressionSessionInvalidate(session)
        }
    }
    @discardableResult
    public func encodeFrame(
        imageBuffer: CVImageBuffer,
        presentationTimeStamp: CMTime,
        duration: CMTime,
        frameProperties: NSDictionary? = nil
    ) throws -> VTEncodeInfoFlags {
        var infoFlags = VTEncodeInfoFlags()
        
        let status = VTCompressionSessionEncodeFrame(session, imageBuffer: imageBuffer, presentationTimeStamp: presentationTimeStamp, duration: duration, frameProperties: frameProperties, sourceFrameRefcon: nil, infoFlagsOut: &infoFlags)
        try OSStatusError.check(status,
                                errorDescription: "failed to encode frame \(imageBuffer) presentationTimeStamp: \(presentationTimeStamp) duration\(duration) frameProperties \(frameProperties as Any) info flags: \(infoFlags)")
        
        return infoFlags
    }
}
