import SwiftUI

/// A scrolling view that displays transcription results.
/// Partial results are shown in gray italic; final results in normal text.
struct TranscriptTextView: View {
    let lines: [TranscriptLine]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(lines) { line in
                        Text(line.text)
                            .font(.body)
                            .foregroundStyle(line.isPartial ? .secondary : .primary)
                            .italic(line.isPartial)
                            .id(line.id)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: lines.count) {
                if let last = lines.last {
                    withAnimation {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }
}
