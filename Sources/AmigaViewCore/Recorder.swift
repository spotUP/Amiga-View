import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation

/// Writes the displayed picture (H.264) and the received sound (AAC) to a .mov. Frames and PCM are
/// pushed in from any thread; encoding runs on its own queue and a backlog is dropped, never waited for.
/// Video times come from frame arrival relative to the first frame (the stream can stall); audio is
/// timed by sample count from that first frame.
public final class Recorder {
    /// Frames queued for encoding beyond which new ones are dropped.
    public static let maxPendingFrames = 25

    public let url: URL
    public let crop: CGRect
    public let size: CGSize
    public let hasAudio: Bool

    private let queue = DispatchQueue(label: "Recorder", qos: .userInitiated)
    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let audioInput: AVAssetWriterInput?
    private let audioFormat: CMAudioFormatDescription
    // Touched only on `queue`.
    private var firstFrameTime: TimeInterval?
    private var lastVideoSeconds: TimeInterval = 0
    private var audioFrames: Int64 = 0
    private var leftover = Data()
    // Guarded by `lock`.
    private let lock = NSLock()
    private var pending = 0
    private var closed = false
    private var dropped = 0

    public init(url: URL, crop: CGRect = ViewGeometry.fullField, withAudio: Bool) throws {
        self.url = url; self.crop = crop; hasAudio = withAudio
        size = ViewGeometry.displaySize(of: crop.integral)
        writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width), AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 6_000_000, AVVideoMaxKeyFrameIntervalKey: 50],
        ])
        videoInput.expectsMediaDataInRealTime = true
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width), kCVPixelBufferHeightKey as String: Int(size.height),
        ])
        var asbd = AudioStreamBasicDescription(mSampleRate: AudioStreamClient.sampleRate, mFormatID: kAudioFormatLinearPCM,
                                               mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
                                               mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4,
                                               mChannelsPerFrame: 2, mBitsPerChannel: 16, mReserved: 0)
        var fd: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil, magicCookieSize: 0,
                                       magicCookie: nil, extensions: nil, formatDescriptionOut: &fd)
        audioFormat = fd!
        if withAudio {
            let a = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: AudioStreamClient.sampleRate,
                AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 128_000,
            ])
            a.expectsMediaDataInRealTime = true
            audioInput = a
            writer.add(a)
        } else {
            audioInput = nil
        }
        writer.add(videoInput)
        guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        writer.startSession(atSourceTime: .zero)
    }

    /// Frames and audio chunks dropped because the encoder fell behind or was not ready.
    public var droppedCount: Int { lock.lock(); defer { lock.unlock() }; return dropped }

    /// Queues a field for encoding; `time` is its arrival in seconds on any steady clock.
    public func push(frame: CGImage, at time: TimeInterval) {
        lock.lock()
        guard !closed, pending < Self.maxPendingFrames else { dropped += 1; lock.unlock(); return }
        pending += 1
        lock.unlock()
        queue.async {
            self.write(frame, at: time)
            self.lock.lock(); self.pending -= 1; self.lock.unlock()
        }
    }

    /// Queues raw s16le stereo PCM. Sound before the first frame is ignored.
    public func push(pcm: Data) {
        guard hasAudio else { return }
        lock.lock(); let isClosed = closed; lock.unlock()
        if !isClosed { queue.async { self.write(pcm: pcm) } }
    }

    /// Finishes the file; `completion` runs on an arbitrary queue once it is playable.
    public func finish(completion: @escaping () -> Void) {
        lock.lock(); closed = true; lock.unlock()
        queue.async {
            guard self.writer.status == .writing else { completion(); return }
            let audioEnd = Double(self.audioFrames) / AudioStreamClient.sampleRate
            self.writer.endSession(atSourceTime: CMTime(seconds: max(self.lastVideoSeconds, audioEnd), preferredTimescale: 90000))
            self.videoInput.markAsFinished()
            self.audioInput?.markAsFinished()
            self.writer.finishWriting(completionHandler: completion)
        }
    }

    /// Blocks until the file is finished; for quitting.
    public func finishAndWait() {
        let done = DispatchSemaphore(value: 0)
        finish { done.signal() }
        done.wait()
    }

    private func drop() { lock.lock(); dropped += 1; lock.unlock() }

    private func write(_ frame: CGImage, at time: TimeInterval) {
        guard writer.status == .writing else { return }
        let start = firstFrameTime ?? time
        let pts = time - start
        guard firstFrameTime == nil || pts > lastVideoSeconds, videoInput.isReadyForMoreMediaData,
              let pool = adaptor.pixelBufferPool, let image = ViewGeometry.displayImage(from: frame, crop: crop)
        else { drop(); return }
        var buffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let pb = buffer else { drop(); return }
        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }
        guard let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pb), width: CVPixelBufferGetWidth(pb), height: CVPixelBufferGetHeight(pb),
                                  bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pb), space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { drop(); return }
        ctx.interpolationQuality = .none
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: ctx.width, height: ctx.height))
        if adaptor.append(pb, withPresentationTime: CMTime(seconds: pts, preferredTimescale: 90000)) {
            firstFrameTime = start
            lastVideoSeconds = pts
        } else { drop() }
    }

    private func write(pcm: Data) {
        guard let audioInput, firstFrameTime != nil, writer.status == .writing else { return }
        let data = leftover + pcm
        let frames = data.count / 4
        leftover = data.suffix(data.count - frames * 4)
        guard frames > 0 else { return }
        let pts = CMTime(value: audioFrames, timescale: Int32(AudioStreamClient.sampleRate))
        audioFrames += Int64(frames)   // the timeline advances even when a chunk is dropped
        guard audioInput.isReadyForMoreMediaData else { drop(); return }
        let length = frames * 4
        var block: CMBlockBuffer?
        var sample: CMSampleBuffer?
        let ok = CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: length, blockAllocator: nil,
                                                    customBlockSource: nil, offsetToData: 0, dataLength: length,
                                                    flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block) == kCMBlockBufferNoErr
        guard ok, let block,
              data.withUnsafeBytes({ CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: length) }) == kCMBlockBufferNoErr,
              CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: nil, dataBuffer: block, formatDescription: audioFormat,
                                                                   sampleCount: frames, presentationTimeStamp: pts,
                                                                   packetDescriptions: nil, sampleBufferOut: &sample) == noErr,
              let sample, audioInput.append(sample)
        else { drop(); return }
    }
}
