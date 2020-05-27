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

public struct EncoderSpecification {
    #if os(macOS)
    /// If set to `true`, only use hardware encode and return an error if this isn't possible. Setting this key automatically implies `enableHardwareAcceleratedVideoEncoder` -- there is no need to set both and the Enable key does nothing if the Require key is set.
    ///
    /// This key is set in the encoderSpecification passed in to VTCompressionSessionCreate.  Set it to `true` to require hardware accelerated encode.  If hardware acceleration is not possible, the VTCompressionSessionCreate call will fail. This key is useful for clients that have their own software encode implementation or those that may want to configure software and hardware encode sessions differently. Hardware acceleration may be unavailable for a number of reasons.  A few common cases are:
    ///        - the machine does not have hardware acceleration capabilities
    ///        - the requested encoding format or encoding configuration is not supported
    ///        - the hardware encoding resources on the machine are busy
    public var requireHardwareAcceleratedVideoEncoder: Bool?
    
    /// If set to `true`, use a hardware accelerated video encoder if available.  If set to `false`, hardware encode will never be used.
    ///
    /// This key is set in the encoderSpecification passed in to `VideoEncoder.init`.  Set it to `true` to allow hardware accelerated encode.  To prevent hardware encode, this property can be set to `false`. In MacOS 10.15 and later, hardware encode is enabled in `VideoEncoder` by default.
    public var enableHardwareAcceleratedVideoEncoder: Bool?
    
    /// Video Encoder Specification
    /// - Parameters:
    ///   - requireHardwareAcceleratedVideoEncoder: If set to `true`, only use hardware encode and return an error if this isn't possible. Setting this key automatically implies `enableHardwareAcceleratedVideoEncoder` -- there is no need to set both and the Enable key does nothing if the Require key is set.
    ///   - enableHardwareAcceleratedVideoEncoder: If set to `true`, use a hardware accelerated video encoder if available.  If set to `false`, hardware encode will never be used.
    public init(
        requireHardwareAcceleratedVideoEncoder: Bool? = nil,
        enableHardwareAcceleratedVideoEncoder: Bool? = nil
    ) {
        self.requireHardwareAcceleratedVideoEncoder = requireHardwareAcceleratedVideoEncoder
        self.enableHardwareAcceleratedVideoEncoder = enableHardwareAcceleratedVideoEncoder
    }
    #else
    public init() {}
    #endif
}

extension EncoderSpecification {
    fileprivate func toDictionary() -> NSDictionary? {
        let dict = NSMutableDictionary()
        #if os(macOS)
        if let requireHardwareAcceleratedVideoEncoder = requireHardwareAcceleratedVideoEncoder {
            dict[kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder] = requireHardwareAcceleratedVideoEncoder
        }
        if let enableHardwareAcceleratedVideoEncoder = enableHardwareAcceleratedVideoEncoder {
            dict[kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder] = enableHardwareAcceleratedVideoEncoder
        }
        #endif
        return dict.count == 0 ? nil : dict
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
        encoderSpecification: EncoderSpecification = .init(),
        imageBufferAttributes: NSDictionary? = nil,
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
            encoderSpecification: encoderSpecification.toDictionary(),
            imageBufferAttributes: imageBufferAttributes,
            compressedDataAllocator: compressedDataAllocator,
            outputCallback: { (selfPointer, _, status, infoFlags, sampleBuffer) in
                let mySelf = Unmanaged<VideoEncoder>.fromOpaque(UnsafeRawPointer(selfPointer!)).takeUnretainedValue()
                
                guard OSStatusError.isSuccessfull(status), let sampleBuffer = sampleBuffer else {
                    print(OSStatusError(status, description: "failed to compress frame"))
                    return
                }
                
                mySelf.callback?(sampleBuffer, infoFlags)
                
        }, refcon: ptr, compressionSessionOut: &session)
        
        guard OSStatusError.isSuccessfull(status), let unwrapedSession = session else {
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
    public func finishEncoding(untilPresenetationTimeStamp: CMTime) {
        VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: untilPresenetationTimeStamp)
    }
}
extension VideoEncoder {
    private func bool(forKey key: CFString) -> Bool {
        var number: NSNumber = .init()
        VTSessionCopyProperty(
            session,
            key: key,
            allocator: nil,
            valueOut: &number
        )
        return number.boolValue
    }
    private func setBool(_ value: Bool, forKey key: CFString) {
        let value = NSNumber(value: value)
        VTSessionSetProperty(session, key: key, value: value)
    }
    
    /// Look into the documentation of [kVTCompressionPropertyKey_AllowFrameReordering](https://developer.apple.com/documentation/videotoolbox/kVTCompressionPropertyKey_AllowFrameReordering) for more information.
    public var allowFrameReordering: Bool {
        get { bool(forKey: kVTCompressionPropertyKey_AllowFrameReordering) }
        set { setBool(newValue, forKey: kVTCompressionPropertyKey_AllowFrameReordering) }
    }
    /// Look into the documentation of [kVTCompressionPropertyKey_RealTime](https://developer.apple.com/documentation/videotoolbox/kVTCompressionPropertyKey_RealTime) for more information.
    public var realTime: Bool {
        get { bool(forKey: kVTCompressionPropertyKey_RealTime) }
        set { setBool(newValue, forKey: kVTCompressionPropertyKey_RealTime) }
    }
    /// Look into the documentation of [kVTCompressionPropertyKey_MaximizePowerEfficiency](https://developer.apple.com/documentation/videotoolbox/kVTCompressionPropertyKey_MaximizePowerEfficiency) for more information.
    public var maximizePowerEfficiency: Bool {
        get { bool(forKey: kVTCompressionPropertyKey_MaximizePowerEfficiency) }
        set { setBool(newValue, forKey: kVTCompressionPropertyKey_MaximizePowerEfficiency) }
    }
}
