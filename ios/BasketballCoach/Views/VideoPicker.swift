import SwiftUI
import PhotosUI
import Foundation

struct VideoPicker: UIViewControllerRepresentable {
    var onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.selectionLimit = 1
        config.filter = .videos
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let provider = results.first?.itemProvider else { return }
            
            // Try different type identifiers for video content
            let videoTypes = ["public.movie", "public.video", "com.apple.quicktime-movie", "public.mpeg-4"]
            
            var foundVideoType: String?
            for videoType in videoTypes {
                if provider.hasItemConformingToTypeIdentifier(videoType) {
                    foundVideoType = videoType
                    break
                }
            }
            
            guard let videoTypeIdentifier = foundVideoType else {
                print("No supported video type found in selected item")
                return
            }
            
            print("Loading video with type identifier: \(videoTypeIdentifier)")
            
            // First try loadDataRepresentation which is more reliable for Photos library content
            provider.loadDataRepresentation(forTypeIdentifier: videoTypeIdentifier) { [weak self] data, error in
                guard let self = self else { return }
                
                if let videoData = data {
                    self.handleVideoData(videoData, typeIdentifier: videoTypeIdentifier)
                } else {
                    print("Failed to load data representation: \(error?.localizedDescription ?? "Unknown error")")
                    // Fallback to file representation
                    self.tryFileRepresentation(provider: provider, typeIdentifier: videoTypeIdentifier)
                }
            }
        }
        
        private func handleVideoData(_ data: Data, typeIdentifier: String) {
            do {
                // Create a unique filename in the app's temp directory
                let tempDir = NSTemporaryDirectory()
                let fileExtension = self.getFileExtension(for: typeIdentifier)
                let fileName = "\(UUID().uuidString).\(fileExtension)"
                let destinationURL = URL(fileURLWithPath: tempDir).appendingPathComponent(fileName)
                
                // Write the data to our temp directory
                try data.write(to: destinationURL)
                
                print("Successfully wrote video data to: \(destinationURL.path)")
                print("File size: \(data.count) bytes")
                
                // Call the completion handler on the main queue
                DispatchQueue.main.async {
                    self.onPick(destinationURL)
                }
            } catch {
                print("Failed to write video data: \(error.localizedDescription)")
            }
        }
        
        private func tryFileRepresentation(provider: NSItemProvider, typeIdentifier: String) {
            provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { [weak self] url, error in
                guard let self = self, let sourceURL = url else {
                    print("Failed to load file representation: \(error?.localizedDescription ?? "Unknown error")")
                    return
                }
                
                // Start accessing the security-scoped resource
                let accessing = sourceURL.startAccessingSecurityScopedResource()
                defer {
                    if accessing {
                        sourceURL.stopAccessingSecurityScopedResource()
                    }
                }
                
                do {
                    // Create a unique filename in the app's temp directory
                    let tempDir = NSTemporaryDirectory()
                    
                    // Preserve the original file extension if possible, otherwise use type identifier
                    let originalExtension = sourceURL.pathExtension.isEmpty ? 
                        self.getFileExtension(for: typeIdentifier) : sourceURL.pathExtension
                    let fileName = "\(UUID().uuidString).\(originalExtension)"
                    let destinationURL = URL(fileURLWithPath: tempDir).appendingPathComponent(fileName)
                    
                    // Copy the file to our temp directory
                    try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                    
                    print("Successfully copied video file to: \(destinationURL.path)")
                    
                    // Call the completion handler on the main queue
                    DispatchQueue.main.async {
                        self.onPick(destinationURL)
                    }
                } catch {
                    print("Failed to copy video file: \(error.localizedDescription)")
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
