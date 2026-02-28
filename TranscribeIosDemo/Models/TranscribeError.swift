import Foundation

enum TranscribeError: LocalizedError {
    case noTranscriptionStream
    case readError
    case unsupportedFormat(String)
    case microphoneAccessDenied
    case audioEngineError(String)

    var errorDescription: String? {
        switch self {
        case .noTranscriptionStream:
            return "No transcription stream returned by Amazon Transcribe."
        case .readError:
            return "Unable to read the source audio file."
        case .unsupportedFormat(let ext):
            return "Unsupported audio format: \(ext)"
        case .microphoneAccessDenied:
            return "Microphone access was denied. Enable it in Settings."
        case .audioEngineError(let detail):
            return "Audio engine error: \(detail)"
        }
    }
}
