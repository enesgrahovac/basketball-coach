import SwiftUI
import PhotosUI
import Photos
import AVFoundation
import Foundation

struct VideoPicker: UIViewControllerRepresentable {
    var onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.selectionLimit = 1
        config.filter = .videos
        config.preferredAssetRepresentationMode = .compatible
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPick: (URL) -> Void
        private var currentItemProvider: NSItemProvider?
        
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let result = results.first else { return }
            
            // Store the item provider for potential fallback use
            currentItemProvider = result.itemProvider
            
            print("=== VIDEO PICKER DEBUG ===")
            print("Asset identifier: \(result.assetIdentifier ?? "nil")")
            print("Item provider types: \(result.itemProvider.registeredTypeIdentifiers)")
            
            // NEW APPROACH: Use Photos framework directly to bypass FileProvider
            if let assetIdentifier = result.assetIdentifier {
                print("Using Photos framework direct access for asset: \(assetIdentifier)")
                loadVideoDirectlyFromPhotos(assetIdentifier: assetIdentifier)
            } else {
                // Fallback to item provider but with more aggressive approach
                print("No asset identifier available, falling back to item provider")
                loadVideoFromItemProvider(result.itemProvider)
            }
        }
        
        private func getCurrentItemProvider() -> NSItemProvider? {
            return currentItemProvider
        }
        
        private func loadVideoDirectlyFromPhotos(assetIdentifier: String) {
            // Check current authorization status first
            let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            
            switch status {
            case .authorized, .limited:
                print("Photo library access already granted, proceeding with asset fetch")
                fetchVideoAsset(assetIdentifier: assetIdentifier)
            case .denied, .restricted:
                print("Photo library access denied/restricted, falling back to item provider")
                // Fall back to the item provider method
                if let provider = getCurrentItemProvider() {
                    loadVideoFromItemProvider(provider)
                }
            case .notDetermined:
                print("Photo library access not determined, requesting permission")
                PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] newStatus in
                    DispatchQueue.main.async {
                        if newStatus == .authorized || newStatus == .limited {
                            self?.fetchVideoAsset(assetIdentifier: assetIdentifier)
                        } else {
                            print("Photo library access denied after request")
                            if let provider = self?.getCurrentItemProvider() {
                                self?.loadVideoFromItemProvider(provider)
                            }
                        }
                    }
                }
            @unknown default:
                print("Unknown photo library authorization status, falling back")
                if let provider = getCurrentItemProvider() {
                    loadVideoFromItemProvider(provider)
                }
            }
        }
        
        private func fetchVideoAsset(assetIdentifier: String) {
            print("=== FETCHING VIDEO ASSET ===")
            let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil)
            guard let asset = fetchResult.firstObject else {
                print("ERROR: Could not find asset with identifier: \(assetIdentifier)")
                // Fall back to item provider
                if let provider = getCurrentItemProvider() {
                    print("Falling back to item provider after asset fetch failure")
                    loadVideoFromItemProvider(provider)
                }
                return
            }
            
            guard asset.mediaType == .video else {
                print("ERROR: Selected asset is not a video, type: \(asset.mediaType.rawValue)")
                if let provider = getCurrentItemProvider() {
                    print("Falling back to item provider after media type check failure")
                    loadVideoFromItemProvider(provider)
                }
                return
            }
            
            print("SUCCESS: Found video asset - duration=\(asset.duration)s, size=\(asset.pixelWidth)x\(asset.pixelHeight)")
            print("Asset creation date: \(asset.creationDate?.description ?? "unknown")")
            print("Asset source type: \(asset.sourceType.rawValue)")
            
            // Request video data directly from Photos framework
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat
            options.version = .current
            
            print("Requesting AVAsset from PHImageManager...")
            
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { [weak self] avAsset, audioMix, info in
                guard let self = self else { return }
                
                print("=== PHImageManager Response ===")
                if let info = info {
                    print("Info dictionary: \(info)")
                }
                
                if let avAsset = avAsset {
                    print("SUCCESS: Got AVAsset from Photos framework")
                    
                    if let urlAsset = avAsset as? AVURLAsset {
                        print("AVAsset is AVURLAsset - attempting direct copy")
                        print("Source URL: \(urlAsset.url)")
                        self.copyVideoFromURL(urlAsset.url)
                    } else {
                        print("AVAsset is not AVURLAsset - exporting video")
                        print("AVAsset type: \(type(of: avAsset))")
                        self.exportVideoAsset(asset)
                    }
                } else {
                    print("ERROR: Could not get AVAsset from PHAsset")
                    // Fall back to item provider
                    if let provider = self.getCurrentItemProvider() {
                        print("Falling back to item provider after AVAsset failure")
                        self.loadVideoFromItemProvider(provider)
                    }
                }
            }
        }
        
        private func copyVideoFromURL(_ sourceURL: URL) {
            print("=== COPYING VIDEO FROM URL ===")
            print("Source URL: \(sourceURL)")
            print("Source URL scheme: \(sourceURL.scheme ?? "none")")
            print("Source URL is file URL: \(sourceURL.isFileURL)")
            
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                
                do {
                    // Verify source file exists and is accessible
                    guard FileManager.default.fileExists(atPath: sourceURL.path) else {
                        print("ERROR: Source file does not exist at: \(sourceURL.path)")
                        self.exportVideoFromURL(sourceURL)
                        return
                    }
                    
                    let attributes = try FileManager.default.attributesOfItem(atPath: sourceURL.path)
                    let fileSize = attributes[.size] as? Int64 ?? 0
                    print("Source file size: \(fileSize) bytes")
                    
                    // Create unique destination in temp directory
                    let tempDir = NSTemporaryDirectory()
                    let timestamp = Int(Date().timeIntervalSince1970)
                    let fileName = "courtvision_direct_\(timestamp)_\(UUID().uuidString).mp4"
                    let destinationURL = URL(fileURLWithPath: tempDir).appendingPathComponent(fileName)
                    
                    print("Copying to: \(destinationURL.path)")
                    
                    // Copy the file
                    try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                    
                    // Verify the copy succeeded
                    guard FileManager.default.fileExists(atPath: destinationURL.path) else {
                        print("ERROR: Copied file does not exist after copy operation")
                        self.exportVideoFromURL(sourceURL)
                        return
                    }
                    
                    let copiedAttributes = try FileManager.default.attributesOfItem(atPath: destinationURL.path)
                    let copiedSize = copiedAttributes[.size] as? Int64 ?? 0
                    print("SUCCESS: Copied file size: \(copiedSize) bytes")
                    
                    guard copiedSize == fileSize else {
                        print("ERROR: File size mismatch after copy. Original: \(fileSize), Copied: \(copiedSize)")
                        try? FileManager.default.removeItem(at: destinationURL)
                        self.exportVideoFromURL(sourceURL)
                        return
                    }
                    
                    print("SUCCESS: Video copied successfully to: \(destinationURL.path)")
                    
                    DispatchQueue.main.async {
                        self.onPick(destinationURL)
                    }
                } catch {
                    print("ERROR: Failed to copy video: \(error)")
                    print("Error details: \((error as NSError).code) - \((error as NSError).domain)")
                    // Fallback to export method
                    self.exportVideoFromURL(sourceURL)
                }
            }
        }
        
        private func exportVideoFromURL(_ sourceURL: URL) {
            let asset = AVAsset(url: sourceURL)
            exportAVAsset(asset)
        }
        
        private func exportVideoAsset(_ asset: PHAsset) {
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat
            
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { [weak self] avAsset, audioMix, info in
                guard let avAsset = avAsset else {
                    print("Could not get AVAsset from PHAsset")
                    return
                }
                
                self?.exportAVAsset(avAsset)
            }
        }
        
        private func exportAVAsset(_ asset: AVAsset) {
            guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetMediumQuality) else {
                print("Could not create export session")
                return
            }
            
            // Create unique output URL
            let tempDir = NSTemporaryDirectory()
            let timestamp = Int(Date().timeIntervalSince1970)
            let fileName = "courtvision_export_\(timestamp)_\(UUID().uuidString).mp4"
            let outputURL = URL(fileURLWithPath: tempDir).appendingPathComponent(fileName)
            
            exportSession.outputURL = outputURL
            exportSession.outputFileType = .mp4
            
            print("Exporting video to: \(outputURL.path)")
            
            exportSession.exportAsynchronously { [weak self] in
                guard let self = self else { return }
                
                switch exportSession.status {
                case .completed:
                    print("Video export completed successfully")
                    DispatchQueue.main.async {
                        self.onPick(outputURL)
                    }
                case .failed:
                    print("Video export failed: \(exportSession.error?.localizedDescription ?? "Unknown error")")
                case .cancelled:
                    print("Video export was cancelled")
                default:
                    print("Video export status: \(exportSession.status.rawValue)")
                }
            }
        }
        
        private func loadVideoFromItemProvider(_ provider: NSItemProvider) {
            // Last resort: use the original item provider method
            print("Using fallback item provider method")
            
            let videoTypes = ["public.movie", "public.video", "com.apple.quicktime-movie", "public.mpeg-4"]
            
            var foundVideoType: String?
            for videoType in videoTypes {
                if provider.hasItemConformingToTypeIdentifier(videoType) {
                    foundVideoType = videoType
                    break
                }
            }
            
            guard let videoTypeIdentifier = foundVideoType else {
                print("No supported video type found in item provider")
                return
            }
            
            // Use data representation to avoid FileProvider URLs
            provider.loadDataRepresentation(forTypeIdentifier: videoTypeIdentifier) { [weak self] data, error in
                guard let self = self else { return }
                
                if let videoData = data, !videoData.isEmpty {
                    print("Successfully loaded video data from item provider: \(videoData.count) bytes")
                    self.handleVideoDataWithVerification(videoData, typeIdentifier: videoTypeIdentifier)
                } else {
                    print("Failed to load data from item provider: \(error?.localizedDescription ?? "No data")")
                }
            }
        }
        
        private func handleVideoDataWithVerification(_ data: Data, typeIdentifier: String) {
            do {
                // Validate data size (ensure it's not empty and not too large)
                guard data.count > 0 else {
                    print("Error: Video data is empty")
                    return
                }
                
                guard data.count < 500_000_000 else { // 500MB limit
                    print("Error: Video file too large (\(data.count) bytes)")
                    return
                }
                
                // Create a unique filename with timestamp to avoid conflicts
                let tempDir = NSTemporaryDirectory()
                let fileExtension = self.getFileExtension(for: typeIdentifier)
                let timestamp = Int(Date().timeIntervalSince1970)
                let fileName = "courtvision_\(timestamp)_\(UUID().uuidString).\(fileExtension)"
                let destinationURL = URL(fileURLWithPath: tempDir).appendingPathComponent(fileName)
                
                // Ensure temp directory exists
                let tempDirURL = URL(fileURLWithPath: tempDir)
                if !FileManager.default.fileExists(atPath: tempDir) {
                    try FileManager.default.createDirectory(at: tempDirURL, withIntermediateDirectories: true, attributes: nil)
                }
                
                // Write the data to our temp directory with atomic operation
                try data.write(to: destinationURL, options: .atomic)
                
                // Verify the file was written successfully
                guard FileManager.default.fileExists(atPath: destinationURL.path) else {
                    print("Error: File was not written successfully")
                    return
                }
                
                // Verify file size matches
                let attributes = try FileManager.default.attributesOfItem(atPath: destinationURL.path)
                let fileSize = attributes[.size] as? Int64 ?? 0
                guard fileSize == data.count else {
                    print("Error: File size mismatch. Expected: \(data.count), Got: \(fileSize)")
                    // Clean up the incomplete file
                    try? FileManager.default.removeItem(at: destinationURL)
                    return
                }
                
                print("Successfully wrote video data to: \(destinationURL.path)")
                print("File size: \(data.count) bytes")
                print("File verified successfully")
                
                // Call the completion handler on the main queue
                DispatchQueue.main.async {
                    self.onPick(destinationURL)
                }
            } catch {
                print("Failed to write video data: \(error.localizedDescription)")
                
                // If it's a write error, we might want to retry with a different filename
                if (error as NSError).domain == NSCocoaErrorDomain {
                    print("CocoaError details: \((error as NSError).code)")
                }
            }
        }
        
        private func getFileExtension(for typeIdentifier: String) -> String {
            switch typeIdentifier {
            case "public.movie", "public.video":
                return "mp4"
            case "com.apple.quicktime-movie":
                return "mov"
            case "public.mpeg-4":
                return "mp4"
            default:
                return "mp4"
            }
        }
    }
}
