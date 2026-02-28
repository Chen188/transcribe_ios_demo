import Foundation
import Combine
import AWSS3
import AWSSDKIdentity
import Smithy
import SmithyIdentity
import SmithyStreams

/// Wraps S3 operations: list buckets, upload files.
@MainActor
final class S3Service: ObservableObject {
    @Published var buckets: [String] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let region = "us-east-1"

    private func makeClient() async throws -> S3Client {
        let creds = StaticAWSCredentialIdentityResolver(
            .init(accessKey: Secrets.accessKey, secret: Secrets.secretKey)
        )
        let config = try await S3Client.S3ClientConfig(
            awsCredentialIdentityResolver: creds,
            region: region
        )
        return S3Client(config: config)
    }

    /// Fetch all bucket names.
    func listBuckets() async {
        isLoading = true
        errorMessage = nil
        do {
            let client = try await makeClient()
            let output = try await client.listBuckets(input: ListBucketsInput())
            buckets = (output.buckets ?? []).compactMap(\.name).sorted()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    /// Upload local file data to S3.
    /// Returns the S3 URI (s3://bucket/key) on success.
    func upload(data: Data, bucket: String, key: String) async throws -> String {
        let client = try await makeClient()
        _ = try await client.putObject(input: PutObjectInput(
            body: .data(data),
            bucket: bucket,
            key: key
        ))
        return "s3://\(bucket)/\(key)"
    }

    /// Download an object from S3 and return its data.
    func getObject(bucket: String, key: String) async throws -> Data {
        let client = try await makeClient()
        let output = try await client.getObject(input: GetObjectInput(
            bucket: bucket,
            key: key
        ))
        guard let body = output.body else {
            throw TranscribeError.readError
        }
        return try await body.readData() ?? Data()
    }

    /// Convert an HTTPS Transcribe output URL to an S3 URI.
    /// Input:  https://s3.us-east-1.amazonaws.com/bucket/key
    ///     or: https://bucket.s3.us-east-1.amazonaws.com/key
    /// Output: s3://bucket/key
    static func httpsToS3Uri(_ urlString: String) -> (bucket: String, key: String)? {
        guard let url = URL(string: urlString),
              let host = url.host else { return nil }

        // Path-style: https://s3.region.amazonaws.com/bucket/key
        if host.hasPrefix("s3.") || host == "s3.amazonaws.com" {
            let pathComponents = url.pathComponents.filter { $0 != "/" }
            guard pathComponents.count >= 2 else { return nil }
            let bucket = pathComponents[0]
            let key = pathComponents.dropFirst().joined(separator: "/")
            return (bucket, key)
        }

        // Virtual-hosted: https://bucket.s3.region.amazonaws.com/key
        if host.contains(".s3.") || host.contains(".s3-") {
            let bucket = host.components(separatedBy: ".s3").first ?? ""
            let key = url.pathComponents.filter { $0 != "/" }.joined(separator: "/")
            guard !bucket.isEmpty, !key.isEmpty else { return nil }
            return (bucket, key)
        }

        return nil
    }
}
