import Foundation
import Combine
import AWSTranscribeStreaming
import AWSClientRuntime
import AWSSDKIdentity
import SmithyIdentity

/// Wraps the AWS Transcribe Streaming SDK for use from SwiftUI.
@MainActor
final class TranscriptionService: ObservableObject {
    @Published var lines: [TranscriptLine] = []
    @Published var isTranscribing = false
    @Published var errorMessage: String?

    private var transcribeTask: Task<Void, Never>?

    // TODO: For production, replace with Cognito identity pool credentials.
    private let region = "us-east-1"

    private func makeCredentialsProvider() -> StaticAWSCredentialIdentityResolver {
        StaticAWSCredentialIdentityResolver(
            .init(
                accessKey: Secrets.accessKey,
                secret: Secrets.secretKey
            )
        )
    }

    /// Start transcribing an audio stream.
    func startTranscription(
        audioStream: AsyncThrowingStream<TranscribeStreamingClientTypes.AudioStream, Error>,
        encoding: TranscribeStreamingClientTypes.MediaEncoding,
        sampleRate: Int,
        languageCode: String = "en-US"
    ) {
        stop()
        lines = []
        errorMessage = nil
        isTranscribing = true

        transcribeTask = Task {
            do {
                try await transcribe(
                    audioStream: audioStream,
                    encoding: encoding,
                    sampleRate: sampleRate,
                    languageCode: languageCode
                )
            } catch is CancellationError {
                // Normal cancellation, ignore.
            } catch {
                errorMessage = error.localizedDescription
            }
            isTranscribing = false
        }
    }

    /// Stop any in-progress transcription.
    func stop() {
        transcribeTask?.cancel()
        transcribeTask = nil
        isTranscribing = false
    }

    // MARK: - Private

    private func transcribe(
        audioStream: AsyncThrowingStream<TranscribeStreamingClientTypes.AudioStream, Error>,
        encoding: TranscribeStreamingClientTypes.MediaEncoding,
        sampleRate: Int,
        languageCode: String
    ) async throws {
        let config = try await TranscribeStreamingClient.TranscribeStreamingClientConfig(
            awsCredentialIdentityResolver: makeCredentialsProvider(),
            region: region
        )
        let client = TranscribeStreamingClient(config: config)

        let output = try await client.startStreamTranscription(
            input: StartStreamTranscriptionInput(
                audioStream: audioStream,
                languageCode: TranscribeStreamingClientTypes.LanguageCode(rawValue: languageCode),
                mediaEncoding: encoding,
                mediaSampleRateHertz: sampleRate
            )
        )

        guard let resultStream = output.transcriptResultStream else {
            throw TranscribeError.noTranscriptionStream
        }

        for try await event in resultStream {
            try Task.checkCancellation()

            switch event {
            case .transcriptevent(let transcriptEvent):
                for result in transcriptEvent.transcript?.results ?? [] {
                    guard let transcript = result.alternatives?.first?.transcript,
                          !transcript.isEmpty else {
                        continue
                    }

                    let isPartial = result.isPartial
                    let line = TranscriptLine(text: transcript, isPartial: isPartial)

                    if isPartial {
                        if let lastIndex = lines.indices.last, lines[lastIndex].isPartial {
                            lines[lastIndex] = line
                        } else {
                            lines.append(line)
                        }
                    } else {
                        if let lastIndex = lines.indices.last, lines[lastIndex].isPartial {
                            lines[lastIndex] = line
                        } else {
                            lines.append(line)
                        }
                    }
                }
            default:
                break
            }
        }
    }
}
