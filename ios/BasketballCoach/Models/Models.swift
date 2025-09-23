import Foundation

struct Clip: Identifiable, Codable {
    let id: String
    let storage_key: String
    let duration_s: Int
    let created_at: Date
}

struct Analysis: Identifiable, Codable {
    let id: String
    let clip_id: String
    let status: String
    let shot_type: String?
    let result: String?
    let confidence: Double?
    let tips_text: String?
    let error_msg: String?
    let created_at: Date
    let started_at: Date?
    let completed_at: Date?
}

struct ClipWithAnalysis: Identifiable, Codable {
    let id: String
    let storage_key: String
    let duration_s: Int
    let created_at: Date
    let analysis_id: String?
    let analysis_status: String?
    let shot_type: String?
    let result: String?
    let confidence: Double?
    let tips_text: String?
    let error_msg: String?
    let analysis_created_at: Date?
    let started_at: Date?
    let completed_at: Date?
    
    var displayShotType: String {
        guard let shotType = shot_type else { return "Unknown" }
        switch shotType {
        case "lay_up": return "Lay-up"
        case "in_paint": return "In Paint"
        case "mid_range": return "Mid-range"
        case "three_pointer": return "3-Pointer"
        case "free_throw": return "Free Throw"
        default: return shotType.capitalized
        }
    }
    
    var displayResult: String {
        guard let result = result else { return "Pending" }
        return result.capitalized
    }
    
    var isComplete: Bool {
        return analysis_status == "success"
    }
    
    var isPending: Bool {
        return analysis_status == "pending" || analysis_status == "processing"
    }
    
    var hasFailed: Bool {
        return analysis_status == "failed"
    }
}

enum AnalysisStatus: String {
    case pending, processing, success, failed
}

enum ShotType: String, CaseIterable {
    case layUp = "lay_up"
    case inPaint = "in_paint"
    case midRange = "mid_range"
    case threePointer = "three_pointer"
    case freeThrow = "free_throw"
    
    var displayName: String {
        switch self {
        case .layUp: return "Lay-up"
        case .inPaint: return "In Paint"
        case .midRange: return "Mid-range"
        case .threePointer: return "3-Pointer"
        case .freeThrow: return "Free Throw"
        }
    }
}

enum ShotResult: String, CaseIterable {
    case make = "make"
    case miss = "miss"
    
    var displayName: String {
        return rawValue.capitalized
    }
}

enum VideoProcessingError: LocalizedError {
    case fileNotFound(String)
    case fileNotAccessible(String)
    case invalidFileFormat(String)
    case copyFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound(let message):
            return "File not found: \(message)"
        case .fileNotAccessible(let message):
            return "File not accessible: \(message)"
        case .invalidFileFormat(let message):
            return "Invalid file format: \(message)"
        case .copyFailed(let message):
            return "Failed to copy file: \(message)"
        }
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let analysisStarted = Notification.Name("analysisStarted")
    static let analysisCompleted = Notification.Name("analysisCompleted")
}
