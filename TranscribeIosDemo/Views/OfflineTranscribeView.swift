import SwiftUI
import UniformTypeIdentifiers

struct OfflineTranscribeView: View {
    @StateObject private var s3 = S3Service()
    @StateObject private var transcribe = OfflineTranscriptionService()

    @State private var selectedBucket: String?
    @State private var uploadedS3Uri: String?
    @State private var jobName: String = ""
    @State private var showFilePicker = false
    @State private var selectedFileData: Data?
    @State private var selectedFileName: String?
    @State private var isProcessing = false

    private var isBucketReady: Bool { selectedBucket != nil }
    private var isFileReady: Bool { selectedFileData != nil }
    private var canStart: Bool { isBucketReady && isFileReady && !jobName.isEmpty && !isProcessing }

    // MARK: - Body

    var body: some View {
        List {
            stepOneSection
            if isBucketReady { stepTwoSection }
            if isBucketReady && isFileReady { stepThreeSection }
            errorSection
            jobsSection
        }
        .task { await s3.listBuckets() }
        .refreshable { await transcribe.listJobs() }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false
        ) { result in
            handleFileSelection(result)
        }
    }

    // MARK: - Step 1: Choose Bucket

    private var stepOneSection: some View {
        Section {
            if s3.isLoading && s3.buckets.isEmpty {
                HStack {
                    ProgressView()
                    Text("Loading buckets...")
                        .foregroundStyle(.secondary)
                }
            } else {
                Picker("S3 Bucket", selection: $selectedBucket) {
                    Text("Choose...").tag(String?.none)
                    ForEach(s3.buckets, id: \.self) { bucket in
                        Text(bucket).tag(String?.some(bucket))
                    }
                }

                if s3.buckets.isEmpty {
                    Button("Retry") {
                        Task { await s3.listBuckets() }
                    }
                    .font(.caption)
                }
            }
        } header: {
            stepHeader(number: 1, title: "Choose S3 Bucket")
        } footer: {
            Text("Audio and transcription results will be stored here.")
        }
    }

    // MARK: - Step 2: Select Audio

    private var stepTwoSection: some View {
        Section {
            HStack(spacing: 12) {
                Button {
                    loadBundledDemo()
                } label: {
                    Label("Demo WAV", systemImage: "waveform.circle")
                }
                .buttonStyle(.bordered)

                Button {
                    showFilePicker = true
                } label: {
                    Label("Browse...", systemImage: "folder")
                }
                .buttonStyle(.bordered)
            }

            if let name = selectedFileName {
                HStack {
                    Image(systemName: "music.note")
                        .foregroundStyle(.secondary)
                    Text(name)
                        .font(.subheadline)
                    Spacer()
                    if let data = selectedFileData {
                        Text(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            stepHeader(number: 2, title: "Select Audio File")
        }
    }

    // MARK: - Step 3: Upload & Transcribe

    private var stepThreeSection: some View {
        Section {
            TextField("Job name", text: $jobName)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.subheadline.monospaced())

            Button {
                Task { await uploadAndTranscribe() }
            } label: {
                HStack {
                    if isProcessing {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(isProcessing ? processingLabel : "Upload & Start Transcription")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canStart)

            if let uri = uploadedS3Uri {
                Label(uri, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            if let msg = transcribe.statusMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            stepHeader(number: 3, title: "Transcribe")
        } footer: {
            Text("Uploads to s3://\(selectedBucket ?? "")/transcribe-input/, then starts a batch job. Results go to the same bucket.")
        }
    }

    // MARK: - Errors

    @ViewBuilder
    private var errorSection: some View {
        if let error = s3.errorMessage ?? transcribe.errorMessage {
            Section {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
    }

    // MARK: - Jobs

    @ViewBuilder
    private var jobsSection: some View {
        Section {
            Button {
                Task { await transcribe.listJobs() }
            } label: {
                Label("Refresh Jobs", systemImage: "arrow.clockwise")
            }
            .disabled(transcribe.isLoading)

            if transcribe.isLoading && transcribe.jobs.isEmpty {
                ProgressView()
            }

            ForEach(transcribe.jobs) { job in
                JobRow(job: job) {
                    Task { await transcribe.getJobStatus(jobName: job.id, s3: s3) }
                }
            }

            if transcribe.jobs.isEmpty && !transcribe.isLoading {
                Text("No jobs yet. Start a transcription above, or tap Refresh.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Transcription Jobs")
        }
    }

    // MARK: - Helpers

    private var processingLabel: String {
        if uploadedS3Uri == nil { return "Uploading..." }
        return "Starting job..."
    }

    private func stepHeader(number: Int, title: String) -> some View {
        HStack(spacing: 6) {
            Text("\(number)")
                .font(.caption2.bold())
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(.blue))
            Text(title)
        }
    }

    // MARK: - Actions

    private func loadBundledDemo() {
        guard let url = Bundle.main.url(
            forResource: "transcribe-test-file",
            withExtension: "wav"
        ) else {
            transcribe.errorMessage = "Demo file not found in app bundle."
            return
        }
        do {
            selectedFileData = try Data(contentsOf: url)
            selectedFileName = "transcribe-test-file.wav"
            uploadedS3Uri = nil
            jobName = "demo-\(Int(Date().timeIntervalSince1970))"
        } catch {
            transcribe.errorMessage = error.localizedDescription
        }
    }

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            do {
                selectedFileData = try Data(contentsOf: url)
                selectedFileName = url.lastPathComponent
                uploadedS3Uri = nil
                let stem = url.deletingPathExtension().lastPathComponent
                jobName = "\(stem)-\(Int(Date().timeIntervalSince1970))"
            } catch {
                transcribe.errorMessage = error.localizedDescription
            }
        case .failure(let error):
            transcribe.errorMessage = error.localizedDescription
        }
    }

    private func uploadAndTranscribe() async {
        guard let data = selectedFileData,
              let bucket = selectedBucket,
              let fileName = selectedFileName else { return }

        isProcessing = true
        s3.errorMessage = nil
        transcribe.errorMessage = nil
        transcribe.statusMessage = nil

        // Step A: Upload
        do {
            let key = "transcribe-input/\(fileName)"
            let uri = try await s3.upload(data: data, bucket: bucket, key: key)
            uploadedS3Uri = uri

            // Step B: Start job
            await transcribe.startJob(
                jobName: jobName,
                mediaUri: uri,
                outputBucket: bucket
            )

            // Auto-refresh jobs list
            await transcribe.listJobs()
        } catch {
            s3.errorMessage = error.localizedDescription
        }

        isProcessing = false
    }
}

// MARK: - Job Row

private struct JobRow: View {
    let job: TranscriptionJobInfo
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack {
                Text(job.id)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                Spacer()
                StatusBadge(status: job.status)
            }

            // Metadata
            HStack(spacing: 12) {
                if let date = job.createdAt {
                    Label(
                        date.formatted(date: .abbreviated, time: .shortened),
                        systemImage: "clock"
                    )
                }
                if let uri = job.outputUri {
                    Label(uri, systemImage: "doc.text")
                        .textSelection(.enabled)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            // Transcript result
            if let transcript = job.transcript {
                Text(transcript)
                    .font(.callout)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.fill.tertiary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .textSelection(.enabled)
            }

            // Refresh for in-progress jobs
            if job.status != "COMPLETED" && job.status != "FAILED" {
                Button(action: onRefresh) {
                    Label("Check Status", systemImage: "arrow.clockwise")
                        .font(.caption)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Status Badge

private struct StatusBadge: View {
    let status: String

    var body: some View {
        Text(status)
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private var color: Color {
        switch status {
        case "COMPLETED": return .green
        case "FAILED": return .red
        case "IN_PROGRESS": return .orange
        default: return .secondary
        }
    }
}
