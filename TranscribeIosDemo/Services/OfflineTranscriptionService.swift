import Foundation
import Combine
import AWSTranscribe
import AWSSDKIdentity
import SmithyIdentity

/// A single transcription job's summary for display.
struct TranscriptionJobInfo: Identifiable {
    let id: String  // job name
    let status: String
    let createdAt: Date?
    let outputUri: String?
    let transcript: String?
}

/// Wraps the batch (non-streaming) Transcribe API.
@MainActor
final class OfflineTranscriptionService: ObservableObject {
    @Published var jobs: [TranscriptionJobInfo] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var statusMessage: String?

    private let region = "us-east-1"

    private func makeClient() async throws -> TranscribeClient {
        let creds = StaticAWSCredentialIdentityResolver(
            .init(accessKey: Secrets.accessKey, secret: Secrets.secretKey)
        )
        let config = try await TranscribeClient.TranscribeClientConfig(
            awsCredentialIdentityResolver: creds,
            region: region
        )
        return TranscribeClient(config: config)
    }

    /// Start a batch transcription job.
    ///
    /// - Parameters:
    ///   - jobName: Unique name for the job.
    ///   - mediaUri: S3 URI of the audio file (s3://bucket/key).
    ///   - outputBucket: S3 bucket to store the transcription result.
    ///   - languageCode: BCP-47 language code.
    func startJob(
        jobName: String,
        mediaUri: String,
        outputBucket: String,
        languageCode: String = "en-US"
    ) async {
        isLoading = true
        errorMessage = nil
        statusMessage = nil
        do {
            let client = try await makeClient()
            _ = try await client.startTranscriptionJob(input: StartTranscriptionJobInput(
                languageCode: TranscribeClientTypes.LanguageCode(rawValue: languageCode),
                media: TranscribeClientTypes.Media(mediaFileUri: mediaUri),
                outputBucketName: outputBucket,
                transcriptionJobName: jobName
            ))
            statusMessage = "Job '\(jobName)' started."
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    /// List recent transcription jobs.
    func listJobs() async {
        isLoading = true
        errorMessage = nil
        do {
            let client = try await makeClient()
            let output = try await client.listTranscriptionJobs(
                input: ListTranscriptionJobsInput()
            )
            jobs = (output.transcriptionJobSummaries ?? []).map { summary in
                TranscriptionJobInfo(
                    id: summary.transcriptionJobName ?? "unknown",
                    status: summary.transcriptionJobStatus?.rawValue ?? "UNKNOWN",
                    createdAt: summary.creationTime,
                    outputUri: nil,
                    transcript: nil
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    /// Get the status and result of a specific job.
    /// Pass an S3Service to fetch the transcript result via S3 SDK.
    func getJobStatus(jobName: String, s3: S3Service? = nil) async {
        isLoading = true
        errorMessage = nil
        do {
            let client = try await makeClient()
            let output = try await client.getTranscriptionJob(
                input: GetTranscriptionJobInput(transcriptionJobName: jobName)
            )
            guard let job = output.transcriptionJob else {
                errorMessage = "Job not found."
                isLoading = false
                return
            }

            let status = job.transcriptionJobStatus?.rawValue ?? "UNKNOWN"
            let httpsUri = job.transcript?.transcriptFileUri

            // Convert HTTPS URL to s3:// URI for display.
            var s3Uri: String?
            var transcript: String?

            if let uri = httpsUri, let parsed = S3Service.httpsToS3Uri(uri) {
                s3Uri = "s3://\(parsed.bucket)/\(parsed.key)"

                // Fetch transcript content via S3 SDK when completed.
                if status == "COMPLETED", let s3 = s3 {
                    transcript = await fetchTranscriptViaS3(
                        s3: s3, bucket: parsed.bucket, key: parsed.key
                    )
                }
            }

            let info = TranscriptionJobInfo(
                id: jobName,
                status: status,
                createdAt: job.creationTime,
                outputUri: s3Uri ?? httpsUri,
                transcript: transcript
            )
            if let idx = jobs.firstIndex(where: { $0.id == jobName }) {
                jobs[idx] = info
            } else {
                jobs.insert(info, at: 0)
            }

            statusMessage = "Job '\(jobName)': \(status)"
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    /// Fetch the transcript JSON from S3 and extract the text.
    private func fetchTranscriptViaS3(s3: S3Service, bucket: String, key: String) async -> String? {
        do {
            let data = try await s3.getObject(bucket: bucket, key: key)
            // Transcribe output JSON: { "results": { "transcripts": [{ "transcript": "..." }] } }
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let results = json["results"] as? [String: Any],
               let transcripts = results["transcripts"] as? [[String: Any]],
               let text = transcripts.first?["transcript"] as? String {
                return text
            }
        } catch {
            // Fall through — result will show as nil.
        }
        return nil
    }
}
