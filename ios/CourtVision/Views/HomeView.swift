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
            VStack(spacing: 32) {
                // Hero Section
                VStack(spacing: 16) {
                    Text("CourtVision")
                        .font(.system(size: 28, weight: .bold, design: .default))
                        .foregroundColor(.basketballOrange)
                    
                    Text("AI-Powered Basketball Analysis")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.charcoal)
                    
                    Text("Record or upload your shots for instant AI coaching tips")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }
                .basketballCard()
                .basketballPadding()
                
                // Action Buttons
                VStack(spacing: 16) {
                    Button(action: { showCamera = true }) {
                        HStack(spacing: 12) {
                            Image(systemName: "video.circle.fill")
                                .font(.title2)
                            Text("Record Shot")
                        }
                    }
                    .primaryButton()
                    .disabled(isBusy)
                    
                    Button(action: { showPicker = true }) {
                        HStack(spacing: 12) {
                            Image(systemName: "photo.on.rectangle")
                                .font(.title2)
                            Text("Upload from Library")
                        }
                    }
                    .secondaryButton()
                    .disabled(isBusy)
                }

                if isBusy {
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.2)
                            .tint(.basketballOrange)
                        
                        Text(statusText)
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundColor(.basketballOrange)
                            .multilineTextAlignment(.center)
                    }
                    .basketballCard()
                    .basketballPadding()
                }
                
                Spacer()
            }
            .sheet(isPresented: $showPicker) {
                VideoPicker { url in
                    showPicker = false
                    Task { await handleVideoSelected(url: url) }
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraRecorder { url in
                    showCamera = false
                    Task { await handleVideoSelected(url: url) }
                }
            }
            .basketballPadding()
            .background(Color.courtBackground.ignoresSafeArea())
            .navigationTitle("Court")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @MainActor
    private func handleVideoSelected(url: URL) async {
        await processVideoWithRetry(url: url, maxRetries: 3)
    }
    
    @MainActor
    private func processVideoWithRetry(url: URL, maxRetries: Int, currentAttempt: Int = 1) async {
        // Keep track of whether we need to clean up a temporary file
        let isTemporaryFile = url.path.contains(NSTemporaryDirectory())
        
        do {
            isBusy = true
            statusText = currentAttempt > 1 ? "Retrying upload (attempt \(currentAttempt))..." : "Preparing video..."

            // Enhanced file verification
            guard await verifyFileAccess(url: url) else {
                throw VideoProcessingError.fileNotAccessible("File is not accessible at path: \(url.path)")
            }
            
            print("Processing video file at: \(url.path) (attempt \(currentAttempt))")
            
            // Get file attributes safely
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let fileSize = attributes[.size] as? Int64 ?? 0
            print("File size: \(fileSize) bytes")
            
            // Validate file size
            guard fileSize > 0 else {
                throw VideoProcessingError.invalidFileFormat("File appears to be empty")
            }
            
            guard fileSize < 500_000_000 else { // 500MB limit
                throw VideoProcessingError.invalidFileFormat("File too large (\(fileSize) bytes)")
            }

            let data = try Data(contentsOf: url)
            let uuid = UUID().uuidString
            let storageKey = "ios/\(uuid).mp4"

            statusText = "Uploading video..."
            try await uploadVideoWithRetry(data: data, storageKey: storageKey)

            statusText = "Creating records..."
            let clipId = try await db.insertClip(storageKey: storageKey, durationSeconds: 15)
            let analysisId = try await db.insertAnalysis(clipId: clipId)

            // Clean up temporary file after successful upload
            if isTemporaryFile {
                cleanupTemporaryFile(at: url)
            }

            statusText = "Starting analysis..."
            try await analysisService.triggerAnalysis(clipId: clipId, storageKey: storageKey)

            // Success! Switch to History tab
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
            print("Error processing video (attempt \(currentAttempt)): \(error)")
            
            // Determine if we should retry
            let shouldRetry = currentAttempt < maxRetries && isRetryableError(error)
            
            if shouldRetry {
                print("Retrying in 2 seconds...")
                statusText = "Upload failed. Retrying in 2 seconds..."
                
                // Wait before retry
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                
                await processVideoWithRetry(url: url, maxRetries: maxRetries, currentAttempt: currentAttempt + 1)
                return
            }
            
            // Final failure - provide detailed error messages
            if let videoError = error as? VideoProcessingError {
                statusText = "Error: \(videoError.localizedDescription)"
            } else if error is CocoaError {
                let cocoaError = error as NSError
                if cocoaError.code == NSFileReadNoSuchFileError {
                    statusText = "Error: The selected video file is no longer accessible. Please try selecting the video again."
                } else if cocoaError.code == 4097 { // FileProvider error
                    statusText = "Error: File access issue. Please try selecting the video again."
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
    
    private func verifyFileAccess(url: URL) async -> Bool {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    // Check if file exists
                    guard FileManager.default.fileExists(atPath: url.path) else {
                        continuation.resume(returning: false)
                        return
                    }
                    
                    // Try to access file attributes
                    let _ = try FileManager.default.attributesOfItem(atPath: url.path)
                    
                    // Try to read a small portion of the file to verify access
                    let handle = try FileHandle(forReadingFrom: url)
                    defer { handle.closeFile() }
                    let _ = handle.readData(ofLength: 1024) // Read first 1KB
                    
                    continuation.resume(returning: true)
                } catch {
                    print("File access verification failed: \(error)")
                    continuation.resume(returning: false)
                }
            }
        }
    }
    
    private func uploadVideoWithRetry(data: Data, storageKey: String) async throws {
        var lastError: Error?
        
        for attempt in 1...3 {
            do {
                try await storage.uploadVideo(data: data, storageKey: storageKey)
                return // Success
            } catch {
                lastError = error
                print("Upload attempt \(attempt) failed: \(error)")
                
                if attempt < 3 {
                    // Wait before retry with exponential backoff
                    let delay = Double(attempt) * 1.0
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }
        
        // All attempts failed
        throw lastError ?? NSError(domain: "UploadError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Upload failed after 3 attempts"])
    }
    
    private func isRetryableError(_ error: Error) -> Bool {
        if let videoError = error as? VideoProcessingError {
            // Don't retry for file format or file not found errors
            switch videoError {
            case .invalidFileFormat, .fileNotFound:
                return false
            case .fileNotAccessible, .copyFailed:
                return true
            }
        }
        
        if let nsError = error as NSError? {
            // Retry for FileProvider errors and network-related issues
            if nsError.domain == NSCocoaErrorDomain && nsError.code == 4097 {
                return true
            }
            
            // Retry for temporary file access issues
            if nsError.domain == NSCocoaErrorDomain && (
                nsError.code == NSFileReadNoPermissionError ||
                nsError.code == NSFileReadCorruptFileError
            ) {
                return true
            }
        }
        
        // Default to not retrying unknown errors
        return false
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
