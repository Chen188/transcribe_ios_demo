import SwiftUI

struct ContentView: View {
    @StateObject private var realtimeService = TranscriptionService()

    var body: some View {
        TabView {
            NavigationStack {
                MicrophoneView(service: realtimeService)
                    .navigationTitle("Realtime")
            }
            .tabItem {
                Label("Realtime", systemImage: "waveform")
            }

            NavigationStack {
                OfflineTranscribeView()
                    .navigationTitle("Offline")
            }
            .tabItem {
                Label("Offline", systemImage: "doc.text")
            }
        }
    }
}

#Preview {
    ContentView()
}
