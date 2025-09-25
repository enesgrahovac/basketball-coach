import SwiftUI
import Photos

@main
struct CourtVisionApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    requestPhotoLibraryPermissions()
                }
        }
    }
    
    private func requestPhotoLibraryPermissions() {
        // Request photo library access on app launch for better UX
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            DispatchQueue.main.async {
                switch status {
                case .authorized:
                    print("Photo library access granted")
                case .limited:
                    print("Photo library access limited")
                case .denied:
                    print("Photo library access denied")
                case .notDetermined:
                    print("Photo library access not determined")
                case .restricted:
                    print("Photo library access restricted")
                @unknown default:
                    print("Unknown photo library authorization status")
                }
            }
        }
    }
}
