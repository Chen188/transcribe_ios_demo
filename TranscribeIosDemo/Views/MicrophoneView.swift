import SwiftUI
import AVFoundation
import AWSTranscribeStreaming
import UniformTypeIdentifiers

struct MicrophoneView: View {
    @ObservedObject var service: TranscriptionService
    @State private var audioCaptureService = AudioCaptureService()
    @State private var permissionGranted: Bool?
    @State private var showFilePicker = false
    @State private var simulatingFile: String?

    var body: some View {
        VStack(spacing: 0) {
            // Controls
            VStack(spacing: 12) {
                if service.isTranscribing {
                    // Active session indicator + stop
                    HStack(spacing: 10) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(.red)
                                .frame(width: 8, height: 8)
                            Text(simulatingFile ?? "Live Microphone")
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                        }

                        Spacer()

                        Button(role: .destructive) {
                            stopRecording()
                        } label: {
                            Label("Stop", systemImage: "stop.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .controlSize(.small)
                    }
                } else {
                    // Source selection: two rows
                    HStack(spacing: 12) {
                        // Live mic button — full width left
                        Button {
                            startRecording()
                        } label: {
                            Label("Live Microphone", systemImage: "mic.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(permissionGranted == false)

                        // File sources — grouped together
                        Menu {
                            Button {
                                simulateFromBundledDemo()
                            } label: {
                                Label("Built-in Demo (WAV)", systemImage: "waveform.circle")
                            }

                            Button {
                                showFilePicker = true
                            } label: {
                                Label("Choose Audio File...", systemImage: "folder")
                            }
                        } label: {
                            Label("From File", systemImage: "doc.badge.plus")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }

                    if permissionGranted == false {
                        Text("Microphone unavailable — use a file source instead.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()

            Divider()

            if let granted = permissionGranted, !granted, simulatingFile == nil {
                ContentUnavailableView(
                    "Microphone Access Denied",
                    systemImage: "mic.slash",
                    description: Text("Enable microphone access in Settings to use this feature.")
                )
            } else if service.lines.isEmpty && !service.isTranscribing {
                ContentUnavailableView(
                    "No Transcript",
                    systemImage: "waveform",
                    description: Text("Tap Live Microphone or choose a file to start.")
                )
            } else {
                TranscriptTextView(lines: service.lines)
            }

            if let error = service.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding()
            }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                simulateFromFile(at: url)
            case .failure(let error):
                service.errorMessage = error.localizedDescription
            }
        }
        .task {
            permissionGranted = await AudioCaptureService.requestPermission()
        }
    }

    // MARK: - Private

    private func startRecording() {
        simulatingFile = nil
        do {
            let audioStream = try audioCaptureService.startCapture()
            service.startTranscription(
                audioStream: audioStream,
                encoding: .pcm,
                sampleRate: Int(AudioCaptureService.targetSampleRate)
            )
        } catch {
            service.errorMessage = error.localizedDescription
        }
    }

    private func stopRecording() {
        audioCaptureService.stopCapture()
        service.stop()
        simulatingFile = nil
    }

    private func simulateFromBundledDemo() {
        guard let url = Bundle.main.url(
            forResource: "transcribe-test-file",
            withExtension: "wav"
        ) else {
            service.errorMessage = "Demo file not found in app bundle."
            return
        }
        simulatingFile = "transcribe-test-file.wav"
        simulateFromFile(at: url)
    }

    private func simulateFromFile(at url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()

        do {
            let pcmData = try decodeToPCM(url: url)
            if accessed { url.stopAccessingSecurityScopedResource() }

            simulatingFile = url.lastPathComponent
            let audioStream = createRealtimeAudioStream(from: pcmData, sampleRate: 16000)
            service.startTranscription(
                audioStream: audioStream,
                encoding: .pcm,
                sampleRate: 16000
            )
        } catch {
            if accessed { url.stopAccessingSecurityScopedResource() }
            service.errorMessage = error.localizedDescription
        }
    }

    /// Decode any audio file to 16kHz 16-bit PCM mono data.
    private func decodeToPCM(url: URL) throws -> Data {
        let sourceFile = try AVAudioFile(forReading: url)

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16000,
            channels: 1,
            interleaved: true
        ) else {
            throw TranscribeError.audioEngineError("Cannot create target audio format")
        }

        guard let converter = AVAudioConverter(
            from: sourceFile.processingFormat,
            to: targetFormat
        ) else {
            throw TranscribeError.audioEngineError("Cannot create audio converter")
        }

        let frameCount = AVAudioFrameCount(
            16000.0 / sourceFile.processingFormat.sampleRate * Double(sourceFile.length)
        )
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: frameCount
        ) else {
            throw TranscribeError.audioEngineError("Cannot allocate output buffer")
        }

        var isDone = false
        converter.convert(to: outputBuffer, error: nil) { _, outStatus in
            if isDone {
                outStatus.pointee = .endOfStream
                return nil
            }
            let readBuffer = AVAudioPCMBuffer(
                pcmFormat: sourceFile.processingFormat,
                frameCapacity: 4096
            )!
            do {
                try sourceFile.read(into: readBuffer)
                if readBuffer.frameLength == 0 {
                    isDone = true
                    outStatus.pointee = .endOfStream
                    return nil
                }
                outStatus.pointee = .haveData
                return readBuffer
            } catch {
                isDone = true
                outStatus.pointee = .endOfStream
                return nil
            }
        }

        guard let channelData = outputBuffer.int16ChannelData else {
            throw TranscribeError.readError
        }
        let byteCount = Int(outputBuffer.frameLength) * MemoryLayout<Int16>.size
        return Data(bytes: channelData[0], count: byteCount)
    }

    /// Stream audio data in real-time 125ms chunks, simulating live mic input.
    private func createRealtimeAudioStream(
        from audioData: Data,
        sampleRate: Int
    ) -> AsyncThrowingStream<TranscribeStreamingClientTypes.AudioStream, Error> {
        let chunkDuration: Double = 0.125 // 125ms
        let chunkSize = Int(chunkDuration * Double(sampleRate) * 2.0) // 16-bit = 2 bytes/sample
        let audioDataSize = audioData.count

        return AsyncThrowingStream { continuation in
            Task {
                var currentStart = 0
                var currentEnd = min(chunkSize, audioDataSize)

                while currentStart < audioDataSize {
                    try Task.checkCancellation()

                    let dataChunk = audioData[currentStart..<currentEnd]
                    let audioEvent = TranscribeStreamingClientTypes.AudioStream.audioevent(
                        .init(audioChunk: dataChunk)
                    )
                    let result = continuation.yield(audioEvent)
                    if case .terminated = result {
                        continuation.finish()
                        return
                    }

                    currentStart = currentEnd
                    currentEnd = min(currentStart + chunkSize, audioDataSize)

                    // Sleep to simulate real-time playback pace.
                    try await Task.sleep(nanoseconds: UInt64(chunkDuration * 1_000_000_000))
                }
                continuation.finish()
            }
        }
    }
}
