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

struct AnalysisOverride: Identifiable, Codable {
    let id: String
    let analysis_id: String
    let field_name: String
    let original_value: String?
    let override_value: String
    let created_at: Date
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
    
    // Overrides are populated separately via joins or additional queries
    var overrides: [AnalysisOverride]?
    
    // MARK: - Effective Values (with override support)
    
    var effectiveShotType: String? {
        // Return override value if present, otherwise original AI prediction
        return overrides?.first(where: { $0.field_name == "shot_type" })?.override_value ?? shot_type
    }
    
    var effectiveResult: String? {
        // Return override value if present, otherwise original AI prediction  
        return overrides?.first(where: { $0.field_name == "result" })?.override_value ?? result
    }
    
    var hasUserCorrections: Bool {
        return !(overrides?.isEmpty ?? true)
    }
    
    // MARK: - Display Properties
    
    var displayShotType: String {
        guard let shotType = effectiveShotType else { return "Unknown" }
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
        guard let result = effectiveResult else { return "Pending" }
        return result.capitalized
    }
    
    // MARK: - Status Properties
    
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

enum OverrideField: String, CaseIterable {
    case shotType = "shot_type"
    case result = "result"
    
    var displayName: String {
        switch self {
        case .shotType: return "Shot Type"
        case .result: return "Make/Miss"
        }
    }
    
    var validValues: [String] {
        switch self {
        case .shotType:
            return ShotType.allCases.map { $0.rawValue }
        case .result:
            return ShotResult.allCases.map { $0.rawValue }
        }
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
