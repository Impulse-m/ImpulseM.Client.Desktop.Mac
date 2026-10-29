import AppKit
import CoreVideo
import Foundation
import LiveKit
import Metal
import MetalEngine
import SwiftSignalKit
import YuvConversion


private func copyI420ToNV12Buffer(
    width: Int,
    height: Int,
    srcY: UnsafePointer<UInt8>,
    strideY: Int,
    srcU: UnsafePointer<UInt8>,
    strideU: Int,
    srcV: UnsafePointer<UInt8>,
    strideV: Int,
    pixelBuffer: CVPixelBuffer
) -> Bool {
    guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange else {
        return false
    }
    guard CVPixelBufferGetWidthOfPlane(pixelBuffer, 0) == width else {
        return false
    }
    guard CVPixelBufferGetHeightOfPlane(pixelBuffer, 0) == height else {
        return false
    }

    let lockResult: CVReturn = CVPixelBufferLockBaseAddress(pixelBuffer, [])
    if lockResult != kCVReturnSuccess {
        return false
    }
    defer {
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
    }

    guard let dstY = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else {
        return false
    }
    let dstStrideY: Int = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)

    guard let dstUV = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1) else {
        return false
    }
    let dstStrideUV: Int = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)

    LibYUVConverter.i420ToNV12(
        withSrcY: srcY,
        srcStrideY: Int32(strideY),
        srcU: srcU,
        srcStrideU: Int32(strideU),
        srcV: srcV,
        srcStrideV: Int32(strideV),
        dstY: dstY.assumingMemoryBound(to: UInt8.self),
        dstStrideY: Int32(dstStrideY),
        dstUV: dstUV.assumingMemoryBound(to: UInt8.self),
        dstStrideUV: Int32(dstStrideUV),
        width: Int32(width),
        height: Int32(height)
    )
    return true
}


/// Receives the frames of a LiveKit video track on the LiveKit thread and hands them to the adapter.
private final class LiveKitTrackFrameRenderer: NSObject, VideoRenderer {
    var onFrame: ((VideoFrame) -> Void)?


    var adaptiveStreamSize: CGSize {
        return .zero
    }


    var isAdaptiveStreamEnabled: Bool {
        return false
    }


    func set(size: CGSize) {
    }


    func render(frame: VideoFrame) {
        self.onFrame?(frame)
    }
}


/// Turns the frames of a LiveKit video track into the Metal texture outputs that the call video view draws.
private final class AdaptedCallVideoSource: VideoSource {
    final class PixelBufferPool {
        let width: Int
        let height: Int
        let pool: CVPixelBufferPool

        init?(width: Int, height: Int) {
            self.width = width
            self.height = height

            let bufferOptions: [String: Any] = [
                kCVPixelBufferPoolMinimumBufferCountKey as String: 4 as NSNumber
            ]
            let pixelBufferOptions: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange as NSNumber,
                kCVPixelBufferWidthKey as String: width as NSNumber,
                kCVPixelBufferHeightKey as String: height as NSNumber,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:] as NSDictionary
            ]

            var pool: CVPixelBufferPool?
            CVPixelBufferPoolCreate(nil, bufferOptions as CFDictionary, pixelBufferOptions as CFDictionary, &pool)
            guard let pool else {
                return nil
            }
            self.pool = pool
        }
    }


    final class PixelBufferPoolState {
        var pool: PixelBufferPool?
    }


    private let queue: Queue
    private let track: VideoTrack
    private let renderer: LiveKitTrackFrameRenderer
    private let mirrorHorizontally: Bool
    private var onUpdatedListeners = Bag<() -> Void>()
    private(set) var currentOutput: Output?

    private var textureCache: CVMetalTextureCache?
    private var pixelBufferPoolState: QueueLocalObject<PixelBufferPoolState>


    init(track: VideoTrack, mirrorHorizontally: Bool) {
        let queue: Queue = Queue(name: "AdaptedCallVideoSource")
        self.queue = queue
        self.pixelBufferPoolState = QueueLocalObject(queue: queue, generate: {
            return PixelBufferPoolState()
        })
        self.track = track
        self.mirrorHorizontally = mirrorHorizontally
        self.renderer = LiveKitTrackFrameRenderer()

        CVMetalTextureCacheCreate(nil, nil, MetalEngine.shared.device, nil, &self.textureCache)

        self.renderer.onFrame = { [weak self] frame in
            self?.handleFrame(frame)
        }
        self.track.add(videoRenderer: self.renderer)
    }


    func addOnUpdated(_ f: @escaping () -> Void) -> Disposable {
        let index = self.onUpdatedListeners.add(f)

        return ActionDisposable { [weak self] in
            DispatchQueue.main.async {
                guard let self else {
                    return
                }
                self.onUpdatedListeners.remove(index)
            }
        }
    }


    deinit {
        self.track.remove(videoRenderer: self.renderer)
    }


    private func handleFrame(_ frame: VideoFrame) {
        guard let textureCache = self.textureCache else {
            return
        }

        let rotationAngle: Float
        switch frame.rotation.rawValue {
        case 90:
            rotationAngle = Float.pi * 0.5
        case 180:
            rotationAngle = Float.pi
        case 270:
            rotationAngle = Float.pi * 3.0 / 2.0
        default:
            rotationAngle = 0.0
        }

        let mirrorDirection: VideoSourceOutput.MirrorDirection = self.mirrorHorizontally ? [.horizontal] : []
        let sourceId: Int = self.mirrorHorizontally ? 1 : 0
        let buffer: VideoBuffer = frame.buffer

        self.queue.async { [weak self] in
            guard let self else {
                return
            }

            let output: VideoSourceOutput?
            if let cvBuffer = buffer as? CVPixelVideoBuffer {
                output = AdaptedCallVideoSource.makeNativeOutput(
                    pixelBuffer: cvBuffer.pixelBuffer,
                    textureCache: textureCache,
                    rotationAngle: rotationAngle,
                    mirrorDirection: mirrorDirection,
                    sourceId: sourceId
                )
            } else {
                guard let i420Buffer = buffer.toI420() else {
                    return
                }
                output = self.makeI420Output(
                    i420Buffer: i420Buffer,
                    textureCache: textureCache,
                    rotationAngle: rotationAngle,
                    mirrorDirection: mirrorDirection,
                    sourceId: sourceId
                )
            }

            guard let output else {
                return
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }
                self.currentOutput = output
                for onUpdated in self.onUpdatedListeners.copyItems() {
                    onUpdated()
                }
            }
        }
    }


    /// A frame that already lives in a pixel buffer: a biplanar YUV buffer is sampled as Y and UV planes, a BGRA buffer as one texture.
    private static func makeNativeOutput(
        pixelBuffer: CVPixelBuffer,
        textureCache: CVMetalTextureCache,
        rotationAngle: Float,
        mirrorDirection: VideoSourceOutput.MirrorDirection,
        sourceId: Int
    ) -> VideoSourceOutput? {
        if CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA {
            let width: Int = CVPixelBufferGetWidth(pixelBuffer)
            let height: Int = CVPixelBufferGetHeight(pixelBuffer)

            var cvMetalTexture: CVMetalTexture?
            let status: CVReturn = CVMetalTextureCacheCreateTextureFromImage(nil, textureCache, pixelBuffer, nil, .bgra8Unorm, width, height, 0, &cvMetalTexture)
            guard status == kCVReturnSuccess, let cvMetalTexture, let bgraTexture = CVMetalTextureGetTexture(cvMetalTexture) else {
                return nil
            }

            return VideoSourceOutput(
                resolution: CGSize(width: CGFloat(bgraTexture.width), height: CGFloat(bgraTexture.height)),
                textureLayout: .bgra(VideoSourceOutput.BGRATextureLayout(bgra: bgraTexture)),
                dataBuffer: VideoSourceOutput.NativeDataBuffer(pixelBuffer: pixelBuffer),
                rotationAngle: rotationAngle,
                followsDeviceOrientation: false,
                mirrorDirection: mirrorDirection,
                sourceId: sourceId,
                textureReferences: [cvMetalTexture],
                textureCache: textureCache
            )
        }

        guard CVPixelBufferGetPlaneCount(pixelBuffer) == 2 else {
            return nil
        }
        let yWidth: Int = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let yHeight: Int = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)

        var cvMetalTextureY: CVMetalTexture?
        var status: CVReturn = CVMetalTextureCacheCreateTextureFromImage(nil, textureCache, pixelBuffer, nil, .r8Unorm, yWidth, yHeight, 0, &cvMetalTextureY)
        guard status == kCVReturnSuccess, let cvMetalTextureY, let yTexture = CVMetalTextureGetTexture(cvMetalTextureY) else {
            return nil
        }

        var cvMetalTextureUV: CVMetalTexture?
        status = CVMetalTextureCacheCreateTextureFromImage(nil, textureCache, pixelBuffer, nil, .rg8Unorm, CVPixelBufferGetWidthOfPlane(pixelBuffer, 1), CVPixelBufferGetHeightOfPlane(pixelBuffer, 1), 1, &cvMetalTextureUV)
        guard status == kCVReturnSuccess, let cvMetalTextureUV, let uvTexture = CVMetalTextureGetTexture(cvMetalTextureUV) else {
            return nil
        }

        return VideoSourceOutput(
            resolution: CGSize(width: CGFloat(yTexture.width), height: CGFloat(yTexture.height)),
            textureLayout: .biPlanar(VideoSourceOutput.BiPlanarTextureLayout(
                y: yTexture,
                uv: uvTexture
            )),
            dataBuffer: VideoSourceOutput.NativeDataBuffer(pixelBuffer: pixelBuffer),
            rotationAngle: rotationAngle,
            followsDeviceOrientation: false,
            mirrorDirection: mirrorDirection,
            sourceId: sourceId,
            textureReferences: [cvMetalTextureY, cvMetalTextureUV],
            textureCache: textureCache
        )
    }


    /// An I420 frame is copied into a pooled NV12 pixel buffer, then sampled as Y and UV planes.
    private func makeI420Output(
        i420Buffer: I420VideoBuffer,
        textureCache: CVMetalTextureCache,
        rotationAngle: Float,
        mirrorDirection: VideoSourceOutput.MirrorDirection,
        sourceId: Int
    ) -> VideoSourceOutput? {
        guard let pixelBufferPoolState = self.pixelBufferPoolState.unsafeGet() else {
            return nil
        }

        let width: Int = Int(i420Buffer.width)
        let height: Int = Int(i420Buffer.height)

        let pool: PixelBufferPool
        if let current = pixelBufferPoolState.pool, current.width == width, current.height == height {
            pool = current
        } else {
            guard let created = PixelBufferPool(width: width, height: height) else {
                return nil
            }
            pixelBufferPoolState.pool = created
            pool = created
        }

        let auxAttributes: [String: Any] = [kCVPixelBufferPoolAllocationThresholdKey as String: 5 as NSNumber]
        var pixelBuffer: CVPixelBuffer?
        let result: CVReturn = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault, pool.pool, auxAttributes as CFDictionary, &pixelBuffer)
        if result == kCVReturnWouldExceedAllocationThreshold {
            print("kCVReturnWouldExceedAllocationThreshold, dropping frame")
            return nil
        }
        guard let pixelBuffer else {
            return nil
        }

        let copied: Bool = i420Buffer.withUnsafePlanes { planes in
            return copyI420ToNV12Buffer(
                width: width,
                height: height,
                srcY: planes.dataY,
                strideY: Int(planes.strideY),
                srcU: planes.dataU,
                strideU: Int(planes.strideU),
                srcV: planes.dataV,
                strideV: Int(planes.strideV),
                pixelBuffer: pixelBuffer
            )
        }
        if !copied {
            return nil
        }

        var cvMetalTextureY: CVMetalTexture?
        var status: CVReturn = CVMetalTextureCacheCreateTextureFromImage(nil, textureCache, pixelBuffer, nil, .r8Unorm, width, height, 0, &cvMetalTextureY)
        guard status == kCVReturnSuccess, let cvMetalTextureY, let yTexture = CVMetalTextureGetTexture(cvMetalTextureY) else {
            return nil
        }

        var cvMetalTextureUV: CVMetalTexture?
        status = CVMetalTextureCacheCreateTextureFromImage(nil, textureCache, pixelBuffer, nil, .rg8Unorm, CVPixelBufferGetWidthOfPlane(pixelBuffer, 1), CVPixelBufferGetHeightOfPlane(pixelBuffer, 1), 1, &cvMetalTextureUV)
        guard status == kCVReturnSuccess, let cvMetalTextureUV, let uvTexture = CVMetalTextureGetTexture(cvMetalTextureUV) else {
            return nil
        }

        return VideoSourceOutput(
            resolution: CGSize(width: CGFloat(yTexture.width), height: CGFloat(yTexture.height)),
            textureLayout: .biPlanar(VideoSourceOutput.BiPlanarTextureLayout(
                y: yTexture,
                uv: uvTexture
            )),
            dataBuffer: VideoSourceOutput.NativeDataBuffer(pixelBuffer: pixelBuffer),
            rotationAngle: rotationAngle,
            followsDeviceOrientation: false,
            mirrorDirection: mirrorDirection,
            sourceId: sourceId,
            textureReferences: [cvMetalTextureY, cvMetalTextureUV],
            textureCache: textureCache
        )
    }
}


/// Follows a signal of LiveKit video tracks and renders the track it currently emits. It has no output while the signal emits nil.
private final class SignalCallVideoSource: VideoSource {
    private let mirrorHorizontally: Bool
    private var onUpdatedListeners = Bag<() -> Void>()
    private var trackDisposable: Disposable?
    private var adaptedSource: AdaptedCallVideoSource?
    private var adaptedUpdatedDisposable: Disposable?


    var currentOutput: VideoSource.Output? {
        return self.adaptedSource?.currentOutput
    }


    init(trackSignal: Signal<VideoTrack?, NoError>, mirrorHorizontally: Bool) {
        self.mirrorHorizontally = mirrorHorizontally
        self.trackDisposable = deliverOnMainQueue(trackSignal).start(next: { [weak self] (track: VideoTrack?) in
            self?.adoptTrack(track)
        })
    }


    func addOnUpdated(_ f: @escaping () -> Void) -> Disposable {
        let index = self.onUpdatedListeners.add(f)

        return ActionDisposable { [weak self] in
            DispatchQueue.main.async {
                guard let self else {
                    return
                }
                self.onUpdatedListeners.remove(index)
            }
        }
    }


    private func adoptTrack(_ track: VideoTrack?) {
        self.adaptedUpdatedDisposable?.dispose()
        self.adaptedUpdatedDisposable = nil

        guard let track else {
            self.adaptedSource = nil
            self.notifyUpdated()
            return
        }

        let adaptedSource: AdaptedCallVideoSource = AdaptedCallVideoSource(track: track, mirrorHorizontally: self.mirrorHorizontally)
        self.adaptedSource = adaptedSource
        self.adaptedUpdatedDisposable = adaptedSource.addOnUpdated { [weak self] in
            self?.notifyUpdated()
        }
        self.notifyUpdated()
    }


    private func notifyUpdated() {
        for onUpdated in self.onUpdatedListeners.copyItems() {
            onUpdated()
        }
    }


    deinit {
        self.trackDisposable?.dispose()
        self.adaptedUpdatedDisposable?.dispose()
    }
}


/// Builds a Metal video source that renders the frames of a LiveKit video track (a remote track or the local camera or screen track).
public func MetalVideoMakeSource(track: VideoTrack, mirrorHorizontally: Bool) -> VideoSource {
    return AdaptedCallVideoSource(track: track, mirrorHorizontally: mirrorHorizontally)
}


/// Builds a Metal video source that follows a signal of LiveKit video tracks. It renders the track as soon as the signal emits one, and follows each later track change, so it can be returned before the track exists.
public func MetalVideoMakeSource(trackSignal: Signal<VideoTrack?, NoError>, mirrorHorizontally: Bool) -> VideoSource {
    return SignalCallVideoSource(trackSignal: trackSignal, mirrorHorizontally: mirrorHorizontally)
}

#if arch(arm64)
public let isMetalVideoRenderingAvailable: Bool = MTLCreateSystemDefaultDevice() != nil
#else
public let isMetalVideoRenderingAvailable: Bool = false
#endif

public func MetalVideoMakeView(videoSource: VideoSource) -> MetalCallVideoView {
    let view = MetalCallVideoView(frame: NSMakeRect(0, 0, 300, 300))
    view.video = videoSource
    return view
}

public func MetalVideoMakeView(track: VideoTrack, mirrorHorizontally: Bool) -> MetalCallVideoView {
    let view = MetalCallVideoView(frame: NSMakeRect(0, 0, 300, 300))
    view.video = MetalVideoMakeSource(track: track, mirrorHorizontally: mirrorHorizontally)
    return view
}
