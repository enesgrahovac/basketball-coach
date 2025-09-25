import SwiftUI
import AVKit
import Combine

struct VideoPlayerView: View {
    let videoURL: URL
    @State var clipData: ClipWithAnalysis // Changed to @State to allow updates
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var isLoading = true
    @State private var hasError = false
    @State private var errorMessage = ""
    @State private var cancellables = Set<AnyCancellable>()
    @State private var showingOverrideSheet = false
    @State private var isUpdatingOverride = false
    
    private let db = DatabaseService()
    
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
                                .foregroundColor(.basketballOrange)
                                .fontWeight(.semibold)
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
                                    .tint(.basketballOrange)
                                    .scaleEffect(1.2)
                                Text("Loading video...")
                                    .font(.caption)
                                    .foregroundColor(.white)
                            }
                        )
                }
                
                // Analysis Information
                ScrollView {
                    VStack(spacing: 20) {
                        // Shot Analysis Header Card
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Shot Analysis")
                                        .font(.title2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.basketballOrange)
                                    Text(formatDate(clipData.created_at))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                            
                            // Status Chips with Override Indicators
                            HStack(spacing: 12) {
                                if clipData.isComplete {
                                    HStack(spacing: 8) {
                                        Text(clipData.displayShotType)
                                            .statusChip(type: .shotType)
                                        
                                        Text(clipData.displayResult)
                                            .statusChip(type: clipData.effectiveResult == "make" ? .make : .miss)
                                        
                                        // User correction indicator
                                        if clipData.hasUserCorrections {
                                            HStack(spacing: 4) {
                                                Image(systemName: "person.crop.circle.badge.checkmark")
                                                    .foregroundColor(.basketballOrange)
                                                    .font(.caption)
                                                Text("Corrected")
                                                    .font(.caption2)
                                                    .fontWeight(.medium)
                                                    .foregroundColor(.basketballOrange)
                                            }
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(
                                                RoundedRectangle(cornerRadius: 4)
                                                    .fill(Color.basketballOrange.opacity(0.1))
                                            )
                                        }
                                    }
                                } else if clipData.isPending {
                                    Text("Analyzing...")
                                        .statusChip(type: .pending)
                                } else if clipData.hasFailed {
                                    Text("Analysis Failed")
                                        .statusChip(type: .miss)
                                }
                                
                                Spacer()
                                
                                // Correct Button (only show for completed analysis)
                                if clipData.isComplete && !isUpdatingOverride {
                                    Button(action: {
                                        showingOverrideSheet = true
                                    }) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "pencil")
                                            Text("Correct")
                                        }
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundColor(.basketballOrange)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(Color.basketballOrange, lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                } else if isUpdatingOverride {
                                    HStack(spacing: 4) {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                        Text("Updating...")
                                    }
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                }
                            }
                            
                            if let confidence = clipData.confidence {
                                HStack {
                                    Text("Confidence:")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    Text("\(Int(confidence * 100))%")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.basketballOrange)
                                }
                            }
                        }
                        .basketballCard()
                        .basketballPadding()
                        
                        // Coach Tips Card
                        if let tips = clipData.tips_text, !tips.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Image(systemName: "person.crop.circle.badge.checkmark")
                                        .foregroundColor(.basketballOrange)
                                        .font(.title3)
                                    Text("Coach Tips")
                                        .font(.title3)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.charcoal)
                                    Spacer()
                                }
                                
                                Text(tips)
                                    .font(.body)
                                    .lineSpacing(4)
                                    .foregroundColor(.charcoal)
                            }
                            .basketballCard()
                            .basketballPadding()
                        }
                        
                        // Error Card
                        if let errorMsg = clipData.error_msg, !errorMsg.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.shotMiss)
                                        .font(.title3)
                                    Text("Analysis Error")
                                        .font(.title3)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.shotMiss)
                                    Spacer()
                                }
                                
                                Text(errorMsg)
                                    .font(.body)
                                    .foregroundColor(.shotMiss)
                            }
                            .basketballCard()
                            .basketballPadding()
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                }
                .background(Color.courtBackground)
            }
            .navigationTitle("Shot Analysis")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.basketballOrange)
                    .fontWeight(.semibold)
                }
            }
        }
        .sheet(isPresented: $showingOverrideSheet) {
            OverrideAnalysisView(
                isPresented: $showingOverrideSheet,
                clipData: clipData,
                onSave: handleOverrideSave
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
    
    private func handleOverrideSave(fieldName: String, overrideValue: String, originalValue: String?) {
        print("🔧 VideoPlayerView: handleOverrideSave called")
        print("🔧 Field: \(fieldName), Override: \(overrideValue), Original: \(originalValue ?? "nil")")
        
        guard let analysisId = clipData.analysis_id else {
            print("❌ Error: No analysis ID available for override")
            return
        }
        
        print("🔧 Analysis ID: \(analysisId)")
        
        Task {
            do {
                isUpdatingOverride = true
                
                print("🔧 Calling DatabaseService.updateAnalysisOverride...")
                
                // Update the override in the database
                try await db.updateAnalysisOverride(
                    analysisId: analysisId,
                    fieldName: fieldName,
                    overrideValue: overrideValue,
                    originalValue: originalValue
                )
                
                print("🔧 Database update completed, refreshing clip data...")
                
                // Refresh the clip data to show the new override
                await refreshClipData()
                
                isUpdatingOverride = false
                
                print("✅ Successfully updated override: \(fieldName) = \(overrideValue)")
                
            } catch {
                isUpdatingOverride = false
                print("❌ Error updating override: \(error)")
                print("❌ Error details: \(error.localizedDescription)")
                // TODO: Show error alert to user
            }
        }
    }
    
    private func refreshClipData() async {
        print("🔧 Refreshing clip data...")
        do {
            // Fetch updated clip data with overrides
            let updatedClips = try await db.fetchClipsWithAnalysisAndOverrides()
            print("🔧 Fetched \(updatedClips.count) clips from database")
            
            // Find our specific clip and update it
            if let updatedClip = updatedClips.first(where: { $0.id == clipData.id }) {
                print("🔧 Found updated clip with ID: \(updatedClip.id)")
                print("🔧 Updated clip overrides count: \(updatedClip.overrides?.count ?? 0)")
                if let overrides = updatedClip.overrides {
                    for override in overrides {
                        print("🔧 Override: \(override.field_name) = \(override.override_value)")
                    }
                }
                
                await MainActor.run {
                    clipData = updatedClip
                }
                print("✅ Clip data updated successfully")
            } else {
                print("❌ Could not find updated clip with ID: \(clipData.id)")
            }
        } catch {
            print("❌ Error refreshing clip data: \(error)")
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
