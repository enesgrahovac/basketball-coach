import SwiftUI

struct HomeView: View {
    @State private var showPicker = false
    @State private var showCamera = false
    @State private var isBusy = false
    @State private var statusText = ""
    @Binding var selectedTab: Int

    private let storage = StorageService()
    private let db = DatabaseService()
    private let analysisService = AnalysisService()

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text("Basketball Coach")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Record or upload a basketball shot for AI analysis")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                VStack(spacing: 16) {
                    Button(action: { showCamera = true }) {
                        HStack {
                            Image(systemName: "video.circle.fill")
                                .font(.title2)
                            Text("Record Video")
                                .font(.headline)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red)
                        .cornerRadius(12)
                    }
                    .disabled(isBusy)
                    
                    Button(action: { showPicker = true }) {
                        HStack {
                            Image(systemName: "photo.on.rectangle")
                                .font(.title2)
                            Text("Upload from Library")
                                .font(.headline)
                        }
                        .foregroundColor(.blue)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(12)
                    }
                    .disabled(isBusy)
                }

                if isBusy {
                    VStack(spacing: 8) {
                        ProgressView()
                        Text(statusText)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .sheet(isPresented: $showPicker) {
                VideoPicker { url in
                    Task { await handleVideoSelected(url: url) }
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraRecorder { url in
                    showCamera = false
                    Task { await handleVideoSelected(url: url) }
                }
            }
            .padding()
            .navigationTitle("Record")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func handleVideoSelected(url: URL) async {
        // Keep track of whether we need to clean up a temporary file
        let isTemporaryFile = url.path.contains(NSTemporaryDirectory())
        
        do {
            isBusy = true
            statusText = "Preparing video..."

            // Verify the file exists and is accessible
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw VideoProcessingError.fileNotFound("File not found at path: \(url.path)")
            }
            
            print("Processing video file at: \(url.path)")
            print("File size: \(try FileManager.default.attributesOfItem(atPath: url.path)[.size] ?? 0) bytes")

            let data = try Data(contentsOf: url)
            let uuid = UUID().uuidString
            let storageKey = "ios/\(uuid).mp4"

            statusText = "Uploading video..."
            try await storage.uploadVideo(data: data, storageKey: storageKey)

            statusText = "Creating records..."
            let clipId = try await db.insertClip(storageKey: storageKey, durationSeconds: 15)
            let analysisId = try await db.insertAnalysis(clipId: clipId)

            // Clean up temporary file after successful upload
            if isTemporaryFile {
                cleanupTemporaryFile(at: url)
            }

            statusText = "Starting analysis..."
            try await analysisService.triggerAnalysis(clipId: clipId, storageKey: storageKey)

            // Switch to History tab and start background analysis
            DispatchQueue.main.async {
                self.selectedTab = 1 // Switch to History tab
                self.isBusy = false
                self.statusText = ""
            }
            
            // Post notification that analysis has started
            NotificationCenter.default.post(
                name: .analysisStarted,
                object: nil,
                userInfo: ["analysisId": analysisId, "clipId": clipId]
            )
            
        } catch {
            print("Error processing video: \(error)")
            
            // Provide more specific error messages
            if let videoError = error as? VideoProcessingError {
                statusText = "Error: \(videoError.localizedDescription)"
            } else if error is CocoaError {
                let cocoaError = error as NSError
                if cocoaError.code == NSFileReadNoSuchFileError {
                    statusText = "Error: The selected video file is no longer accessible. Please try selecting the video again."
                } else {
                    statusText = "Error: Unable to read the video file. \(error.localizedDescription)"
                }
            } else {
                statusText = "Error: \(error.localizedDescription)"
            }
            
            // Clean up temporary file even on error
            if isTemporaryFile {
                cleanupTemporaryFile(at: url)
            }
            
            isBusy = false
        }
    }
    
    private func cleanupTemporaryFile(at url: URL) {
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
                print("Cleaned up temporary file: \(url.path)")
            }
        } catch {
            print("Failed to cleanup temporary file: \(error.localizedDescription)")
        }
    }
}

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        HomeView(selectedTab: .constant(0))
    }
}
