import Foundation
import Supabase

final class StorageService {
    private let client = SupabaseClientProvider.shared.client

    func uploadVideo(data: Data, storageKey: String, bucket: String = "clips") async throws {
        let filePath = storageKey
        _ = try await client.storage
            .from(bucket)
            .upload(
                filePath,
                data: data,
                options: FileOptions(contentType: "video/mp4", upsert: true)
            )
    }
    
    func getVideoURL(storageKey: String, bucket: String = "clips", expiresIn: Int = 3600) async throws -> URL {
        // Use secure backend endpoint to generate signed URLs
        // This keeps the service role key safe on the server
        
        print("Original storage key: \(storageKey)")
        
        guard let supabaseURL = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
              !supabaseURL.isEmpty else {
            throw StorageError.invalidURL
        }
        
        // Call our secure backend endpoint
        let endpointURL = URL(string: "\(supabaseURL)/functions/v1/get-signed-url")!
        
        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Add authorization header with anon key (safe for client)
        if let anonKey = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String {
            request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
            request.setValue(anonKey, forHTTPHeaderField: "apikey")
        }
        
        // Request body
        let requestBody = ["storageKey": storageKey]
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw StorageError.invalidURL
            }
            
            print("HTTP Status: \(httpResponse.statusCode)")
            
            if httpResponse.statusCode != 200 {
                if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let errorMessage = errorData["error"] as? String {
                    print("Backend error: \(errorMessage)")
                }
                throw StorageError.backendError
            }
            
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let signedURLString = json["signedUrl"] as? String,
                  let signedURL = URL(string: signedURLString) else {
                throw StorageError.invalidURL
            }
            
            print("Generated signed URL: \(signedURLString)")
            return signedURL
            
        } catch {
            print("Failed to get signed URL: \(error)")
            throw StorageError.networkError
        }
    }
    
    func getVideoThumbnailURL(storageKey: String, bucket: String = "clips", expiresIn: Int = 3600) async throws -> URL? {
        // For now, we'll use the same video URL. In the future, you could generate thumbnails
        // or use a service to extract frames from the video
        return try await getVideoURL(storageKey: storageKey, bucket: bucket, expiresIn: expiresIn)
    }
}

enum StorageError: Error, LocalizedError {
    case invalidURL
    case missingServiceKey
    case backendError
    case networkError
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL received from storage service"
        case .missingServiceKey:
            return "Missing Supabase service role key"
        case .backendError:
            return "Backend error while generating signed URL"
        case .networkError:
            return "Network error while contacting backend"
        }
    }
}
