import AVFoundation
import AmigaViewCore

/// Plays a PCMJitterBuffer on the default output: the render callback pulls 48 kHz stereo floats.
final class AudioPlayer {
    private let engine = AVAudioEngine()
    private let buffer: PCMJitterBuffer

    init(buffer: PCMJitterBuffer) { self.buffer = buffer }

    func start() throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: AudioStreamClient.sampleRate, channels: 2)!
        let buffer = self.buffer
        let source = AVAudioSourceNode(format: format) { _, _, frameCount, ablPointer in
            let abl = UnsafeMutableAudioBufferListPointer(ablPointer)
            let left = abl[0].mData!.assumingMemoryBound(to: Float.self)
            let right = abl[1].mData!.assumingMemoryBound(to: Float.self)
            buffer.read(left: left, right: right, frames: Int(frameCount))
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        try engine.start()
    }

    func stop() { engine.stop() }
}
