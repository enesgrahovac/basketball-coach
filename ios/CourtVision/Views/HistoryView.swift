import SwiftUI

struct HistoryView: View {
    @State private var clips: [ClipWithAnalysis] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedClip: ClipWithAnalysis?
    @State private var videoURL: URL?
    @State private var showingVideoPlayer = false
    @State private var isPreparingVideo = false
    @State private var selectedShotType: ShotType?
    @State private var selectedResult: ShotResult?
    @State private var showingFilters = false
    @State private var backgroundAnalysisIds: Set<String> = []
    
    private let db = DatabaseService()
    private let storage = StorageService()
    private let analysisService = AnalysisService()
    
    // Computed property to ensure we have both clip and video URL before showing player
    private var canShowVideoPlayer: Bool {
        selectedClip != nil && videoURL != nil && !isPreparingVideo
    }
    
    var filteredClips: [ClipWithAnalysis] {
        var filtered = clips
        
        if let shotType = selectedShotType {
            // Filter by effective shot type (considering overrides)
            filtered = filtered.filter { $0.effectiveShotType == shotType.rawValue }
        }
        
        if let result = selectedResult {
            // Filter by effective result (considering overrides)
            filtered = filtered.filter { $0.effectiveResult == result.rawValue }
        }
        
        return filtered
    }
    
    var body: some View {
        NavigationView {
            VStack {
                if isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Loading your clips...")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage = errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.red)
                        Text("Error loading clips")
                            .font(.headline)
                        Text(errorMessage)
                            .font(.body)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                        Button("Retry") {
                            Task { await loadClips() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filteredClips.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "basketball")
                            .font(.system(size: 48))
                            .foregroundColor(.basketballOrange)
                        
                        Text(clips.isEmpty ? "No shots yet" : "No shots match your filters")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.charcoal)
                        
                        Text(clips.isEmpty ? "Head to the Court to record your first basketball shot!" : "Try adjusting your filters to see more shots.")
                            .font(.body)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 24)
                    }
                    .basketballCard()
                    .basketballPadding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(filteredClips) { clip in
                        ClipRowView(clip: clip) {
                            playVideo(clip: clip)
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                    .listStyle(.plain)
                }
            }
            .background(Color.courtBackground.ignoresSafeArea())
            .navigationTitle("Game Film")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        Button(action: { showingFilters.toggle() }) {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                                .foregroundColor(.basketballOrange)
                        }
                        Button(action: { Task { await loadClips() } }) {
                            Image(systemName: "arrow.clockwise")
                                .foregroundColor(.basketballOrange)
                        }
                    }
                }
            }
            .sheet(isPresented: $showingFilters) {
                FilterView(
                    selectedShotType: $selectedShotType,
                    selectedResult: $selectedResult
                )
            }
            .sheet(isPresented: $showingVideoPlayer) {
                Group {
                    if canShowVideoPlayer, let clip = selectedClip, let url = videoURL {
                        VideoPlayerView(videoURL: url, clipData: clip)
                            .onAppear {
                                print("=== SHEET PRESENTATION TRIGGERED ===")
                                print("Creating VideoPlayerView with clip: \(clip.id)")
                            }
                    } else {
                        // Show loading state while preparing video
                        VStack(spacing: 16) {
                            if isPreparingVideo {
                                ProgressView()
                                Text("Preparing video...")
                                    .font(.headline)
                            } else {
                                Text("Error")
                                    .font(.headline)
                                Text("Video data is missing")
                                    .font(.body)
                                Button("Close") {
                                    showingVideoPlayer = false
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                        .padding()
                        .background(Color(.systemBackground))
                        .onAppear {
                            print("ERROR: Missing data - selectedClip: \(selectedClip?.id ?? "nil"), videoURL: \(videoURL?.absoluteString ?? "nil"), isPreparingVideo: \(isPreparingVideo)")
                        }
                    }
                }
                .onDisappear {
                    // Clean up when sheet is dismissed
                    selectedClip = nil
                    videoURL = nil
                    isPreparingVideo = false
                }
            }
        }
        .task {
            await loadClips()
        }
        .onReceive(NotificationCenter.default.publisher(for: .analysisStarted)) { notification in
            if let analysisId = notification.userInfo?["analysisId"] as? String {
                backgroundAnalysisIds.insert(analysisId)
                Task {
                    await handleBackgroundAnalysis(analysisId: analysisId)
                }
            }
        }
    }
    
    private func loadClips() async {
        isLoading = true
        errorMessage = nil
        
        do {
            clips = try await db.fetchClipsWithAnalysisAndOverrides() // Use override-aware fetching
            print("Successfully loaded \(clips.count) clips")
        } catch {
            print("Error loading clips: \(error)")
            errorMessage = "Failed to load clips: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    private func playVideo(clip: ClipWithAnalysis) {
        print("=== PLAY VIDEO CALLED ===")
        print("Clip ID: \(clip.id)")
        print("Storage Key: \(clip.storage_key)")
        print("Analysis Status: \(clip.analysis_status ?? "nil")")
        
        // Show sheet immediately with loading state
        isPreparingVideo = true
        showingVideoPlayer = true
        
        Task {
            do {
                print("Attempting to get video URL for storage key: \(clip.storage_key)")
                let url = try await storage.getVideoURL(storageKey: clip.storage_key)
                print("Generated video URL: \(url)")
                
                // Set all data atomically on the main actor
                await MainActor.run {
                    selectedClip = clip
                    videoURL = url
                    isPreparingVideo = false  // This will allow the video player to show
                    
                    print("Video player data set:")
                    print("- Selected clip: \(selectedClip?.id ?? "nil")")
                    print("- Video URL: \(videoURL?.absoluteString ?? "nil")")
                    print("- Can show player: \(canShowVideoPlayer)")
                    print("- Showing video player: \(showingVideoPlayer)")
                }
            } catch {
                print("Failed to get video URL: \(error)")
                await MainActor.run {
                    isPreparingVideo = false
                    selectedClip = nil
                    videoURL = nil
                    errorMessage = "Failed to load video: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func handleBackgroundAnalysis(analysisId: String) async {
        do {
            // Refresh clips to show the new processing item
            await loadClips()
            
            // Poll for completion in the background
            let result = try await analysisService.pollUntilComplete(analysisId: analysisId)
            
            // Remove from background tracking
            backgroundAnalysisIds.remove(analysisId)
            
            // Refresh clips to show updated status
            await loadClips()
            
            // If analysis succeeded, auto-present the result
            if result.status == "success" {
                // Find the clip that was just completed
                if let completedClip = clips.first(where: { $0.analysis_id == analysisId }) {
                    await MainActor.run {
                        // Auto-open the completed analysis
                        playVideo(clip: completedClip)
                    }
                }
            }
            
        } catch {
            print("Background analysis error: \(error)")
            backgroundAnalysisIds.remove(analysisId)
            await loadClips() // Refresh to show any error state
        }
    }
}

struct ClipRowView: View {
    let clip: ClipWithAnalysis
    let onPlay: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            // Enhanced thumbnail with basketball theme
            Rectangle()
                .fill(LinearGradient(
                    gradient: Gradient(colors: [Color.basketballOrange.opacity(0.1), Color.basketballOrange.opacity(0.05)]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .frame(width: 80, height: 60)
                .cornerRadius(8)
                .overlay(
                    Button(action: {
                        print("Play button tapped for clip: \(clip.id)")
                        onPlay()
                    }) {
                        Image(systemName: "play.circle.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                            .background(Circle().fill(Color.basketballOrange.opacity(0.8)))
                    }
                )
            
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(formatDate(clip.created_at))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.charcoal)
                    Spacer()
                    Text("\(clip.duration_s)s")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.basketballOrange)
                }
                
                HStack(spacing: 8) {
                    if clip.isComplete {
                        Text(clip.displayShotType)
                            .statusChip(type: .shotType)
                        
                        Text(clip.displayResult)
                            .statusChip(type: clip.effectiveResult == "make" ? .make : .miss)
                        
                        // User correction indicator
                        if clip.hasUserCorrections {
                            Image(systemName: "person.crop.circle.badge.checkmark")
                                .foregroundColor(.basketballOrange)
                                .font(.caption)
                        }
                        
                        if let confidence = clip.confidence {
                            Text("\(Int(confidence * 100))%")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                        }
                    } else if clip.isPending {
                        HStack(spacing: 4) {
                            ProgressView()
                                .scaleEffect(0.7)
                                .tint(.basketballOrange)
                            Text("Analyzing...")
                        }
                        .statusChip(type: .pending)
                    } else if clip.hasFailed {
                        Text("Analysis Failed")
                            .statusChip(type: .miss)
                    }
                    
                    Spacer()
                }
                
                if let tips = clip.tips_text, !tips.isEmpty, clip.isComplete {
                    Text(tips)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .padding(.top, 2)
                }
            }
        }
        .padding(16)
        .basketballCard()
        .onTapGesture {
            print("Row tapped for clip: \(clip.id)")
            onPlay()
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct FilterView: View {
    @Binding var selectedShotType: ShotType?
    @Binding var selectedResult: ShotResult?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section("Shot Type") {
                    Picker("Shot Type", selection: $selectedShotType) {
                        Text("All").tag(ShotType?.none)
                        ForEach(ShotType.allCases, id: \.self) { shotType in
                            Text(shotType.displayName).tag(shotType as ShotType?)
                        }
                    }
                    .pickerStyle(.wheel)
                    .tint(.basketballOrange)
                }
                
                Section("Result") {
                    Picker("Result", selection: $selectedResult) {
                        Text("All").tag(ShotResult?.none)
                        ForEach(ShotResult.allCases, id: \.self) { result in
                            Text(result.displayName).tag(result as ShotResult?)
                        }
                    }
                    .pickerStyle(.segmented)
                    .tint(.basketballOrange)
                }
                
                Section {
                    Button("Clear All Filters") {
                        selectedShotType = nil
                        selectedResult = nil
                    }
                    .foregroundColor(.shotMiss)
                    .fontWeight(.medium)
                }
            }
            .navigationTitle("Filter Shots")
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
    }
}

struct HistoryView_Previews: PreviewProvider {
    static var previews: some View {
        HistoryView()
    }
}
