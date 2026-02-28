import AVFoundation
import AWSTranscribeStreaming

/// Captures microphone audio via AVAudioEngine and produces an
/// `AsyncThrowingStream` of Transcribe-compatible audio events.
final class AudioCaptureService {
    private let engine = AVAudioEngine()
    private var isCapturing = false

    /// Target format expected by AWS Transcribe.
    static let targetSampleRate: Double = 16000
    static let targetChannels: AVAudioChannelCount = 1

    /// Returns `true` if a real microphone is available.
    /// False on simulator or when no audio input hardware is present.
    static var isMicrophoneAvailable: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return AVAudioSession.sharedInstance().availableInputs?.isEmpty == false
        #endif
    }

    /// Request microphone permission. Returns `true` if granted.
    /// Returns `false` without prompting if no mic hardware is present.
    static func requestPermission() async -> Bool {
        guard isMicrophoneAvailable else { return false }
        return await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    /// Start capturing microphone audio.
    func startCapture() throws -> AsyncThrowingStream<TranscribeStreamingClientTypes.AudioStream, Error> {
        guard Self.isMicrophoneAvailable else {
            throw TranscribeError.audioEngineError("No microphone available (simulator?)")
        }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw TranscribeError.audioEngineError("Invalid input format: \(inputFormat)")
        }

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Self.targetSampleRate,
            channels: Self.targetChannels,
            interleaved: true
        ) else {
            throw TranscribeError.audioEngineError("Cannot create target audio format")
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw TranscribeError.audioEngineError(
                "Cannot create converter from \(inputFormat) to \(targetFormat)"
            )
        }

        let stream = AsyncThrowingStream<TranscribeStreamingClientTypes.AudioStream, Error> { continuation in
            inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in
                let frameCapacity = AVAudioFrameCount(
                    Self.targetSampleRate / inputFormat.sampleRate * Double(buffer.frameLength)
                )
                guard let convertedBuffer = AVAudioPCMBuffer(
                    pcmFormat: targetFormat,
                    frameCapacity: frameCapacity
                ) else { return }

                var error: NSError?
                let status = converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                    outStatus.pointee = .haveData
                    return buffer
                }

                guard status != .error, error == nil else { return }

                guard let channelData = convertedBuffer.int16ChannelData else { return }
                let byteCount = Int(convertedBuffer.frameLength) * MemoryLayout<Int16>.size
                let data = Data(bytes: channelData[0], count: byteCount)

                let audioEvent = TranscribeStreamingClientTypes.AudioStream.audioevent(
                    .init(audioChunk: data)
                )
                continuation.yield(audioEvent)
            }

            continuation.onTermination = { @Sendable _ in
                inputNode.removeTap(onBus: 0)
            }
        }

        engine.prepare()
        try engine.start()
        isCapturing = true

        return stream
    }

    /// Stop the audio engine and finish the stream.
    func stopCapture() {
        guard isCapturing else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isCapturing = false
    }
}
