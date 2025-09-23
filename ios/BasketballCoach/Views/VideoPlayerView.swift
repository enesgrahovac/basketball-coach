import SwiftUI
import AVKit
import Combine

struct VideoPlayerView: View {
    let videoURL: URL
    let clipData: ClipWithAnalysis
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var isLoading = true
    @State private var hasError = false
    @State private var errorMessage = ""
    @State private var cancellables = Set<AnyCancellable>()
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Video Player
                if hasError {
                    Rectangle()
                        .fill(Color.black)
                        .aspectRatio(16/9, contentMode: .fit)
                        .overlay(
                            VStack(spacing: 16) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.largeTitle)
                                    .foregroundColor(.white)
                                Text("Failed to load video")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                Text(errorMessage)
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.7))
                                    .multilineTextAlignment(.center)
                                Button("Retry") {
                                    setupPlayer()
                                }
                                .foregroundColor(.blue)
                            }
                            .padding()
                        )
                } else if let player = player, !isLoading {
                    VideoPlayer(player: player)
                        .aspectRatio(16/9, contentMode: .fit)
                        .background(Color.black)
                } else {
                    Rectangle()
                        .fill(Color.black)
                        .aspectRatio(16/9, contentMode: .fit)
                        .overlay(
                            VStack(spacing: 8) {
                                ProgressView()
                                    .tint(.white)
                                Text("Loading video...")
                                    .font(.caption)
                                    .foregroundColor(.white)
                            }
                        )
                }
                
                // Analysis Information
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Shot Analysis")
                                    .font(.headline)
                                Text(formatDate(clipData.created_at))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            
                            if clipData.isComplete {
                                HStack(spacing: 8) {
                                    Text(clipData.displayShotType)
                                        .font(.subheadline)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color.blue.opacity(0.1))
                                        .foregroundColor(.blue)
                                        .cornerRadius(8)
                                    
                                    Text(clipData.displayResult)
                                        .font(.subheadline)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(clipData.result == "make" ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
                                        .foregroundColor(clipData.result == "make" ? .green : .red)
                                        .cornerRadius(8)
                                }
                            } else if clipData.isPending {
                                Text("Analyzing...")
                                    .font(.subheadline)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.orange.opacity(0.1))
                                    .foregroundColor(.orange)
                                    .cornerRadius(8)
                            } else if clipData.hasFailed {
                                Text("Analysis Failed")
                                    .font(.subheadline)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.red.opacity(0.1))
                                    .foregroundColor(.red)
                                    .cornerRadius(8)
                            }
                        }
                        
                        if let confidence = clipData.confidence {
                            HStack {
                                Text("Confidence:")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Text("\(Int(confidence * 100))%")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                        }
                        
                        if let tips = clipData.tips_text, !tips.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Coach Tips")
                                    .font(.headline)
                                Text(tips)
                                    .font(.body)
                                    .lineLimit(nil)
                            }
                        }
                        
                        if let errorMsg = clipData.error_msg, !errorMsg.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Error")
                                    .font(.headline)
                                    .foregroundColor(.red)
                                Text(errorMsg)
                                    .font(.body)
                                    .foregroundColor(.red)
                            }
                        }
                    }
                    .padding()
                }
                .background(Color(.systemGroupedBackground))
            }
            .navigationTitle("Video Analysis")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                trailing: Button("Done") {
                    dismiss()
                }
            )
        }
        .onAppear {
            print("=== VIDEO PLAYER VIEW APPEARED ===")
            print("Video URL: \(videoURL)")
            print("Clip ID: \(clipData.id)")
            setupPlayer()
        }
        .onDisappear {
            player?.pause()
        }
    }
    
    private func setupPlayer() {
        print("Setting up player with URL: \(videoURL)")
        
        // Reset states
        isLoading = true
        hasError = false
        errorMessage = ""
        
        player = AVPlayer(url: videoURL)
        
        // Test the URL accessibility
        Task {
            do {
                let (data, response) = try await URLSession.shared.data(from: videoURL)
                if let httpResponse = response as? HTTPURLResponse {
                    print("HTTP Status Code: \(httpResponse.statusCode)")
                    print("Content-Type: \(httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "unknown")")
                    print("Content-Length: \(data.count) bytes")
                } else {
                    print("Non-HTTP response: \(response)")
                }
            } catch {
                print("URL test failed: \(error)")
            }
        }
        
        // Add observer to check when the player is ready
        if let playerItem = player?.currentItem {
            // Observer for when the item is ready to play
            NotificationCenter.default.addObserver(
                forName: .AVPlayerItemNewAccessLogEntry,
                object: playerItem,
                queue: .main
            ) { _ in
                DispatchQueue.main.async {
                    self.isLoading = false
                }
            }
            
            // Observer for failures
            NotificationCenter.default.addObserver(
                forName: .AVPlayerItemFailedToPlayToEndTime,
                object: playerItem,
                queue: .main
            ) { notification in
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.hasError = true
                    if let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error {
                        self.errorMessage = error.localizedDescription
                        print("Player failed to play: \(error)")
                    } else {
                        self.errorMessage = "Unknown playback error"
                    }
                }
            }
            
            // Check the status of the player item
            playerItem.publisher(for: \.status)
                .sink { status in
                    DispatchQueue.main.async {
                        switch status {
                        case .readyToPlay:
                            self.isLoading = false
                            print("Player is ready to play")
                        case .failed:
                            self.isLoading = false
                            self.hasError = true
                            if let error = playerItem.error {
                                self.errorMessage = error.localizedDescription
                                print("Player item failed: \(error)")
                            } else {
                                self.errorMessage = "Failed to load video"
                            }
                        case .unknown:
                            print("Player status unknown")
                        @unknown default:
                            break
                        }
                    }
                }
                .store(in: &cancellables)
        }
        
        // Also add a timeout to stop loading after 10 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            if self.isLoading {
                self.isLoading = false
                self.hasError = true
                self.errorMessage = "Video loading timed out"
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct VideoPlayerView_Previews: PreviewProvider {
    static var previews: some View {
        VideoPlayerView(
            videoURL: URL(string: "https://example.com/video.mp4")!,
            clipData: ClipWithAnalysis(
                id: "1",
                storage_key: "test.mp4",
                duration_s: 30,
                created_at: Date(),
                analysis_id: "1",
                analysis_status: "success",
                shot_type: "three_pointer",
                result: "make",
                confidence: 0.85,
                tips_text: "Great form! Keep your elbow aligned and follow through consistently.",
                error_msg: nil,
                analysis_created_at: Date(),
                started_at: Date(),
                completed_at: Date()
            )
        )
    }
}
