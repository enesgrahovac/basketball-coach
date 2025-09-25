import Foundation
import Supabase

final class DatabaseService {
    private let client = SupabaseClientProvider.shared.client

    func insertClip(storageKey: String, durationSeconds: Int) async throws -> String {
        struct InsertClip: Encodable { let storage_key: String; let duration_s: Int }
        struct Returned: Decodable { let id: String }
        let rows: [Returned] = try await client.database.from("clips").insert(InsertClip(storage_key: storageKey, duration_s: durationSeconds)).select().execute().value
        return rows.first!.id
    }

    func insertAnalysis(clipId: String) async throws -> String {
        struct InsertAnalysis: Encodable { let clip_id: String; let status: String }
        struct Returned: Decodable { let id: String }
        let rows: [Returned] = try await client.database.from("analysis").insert(InsertAnalysis(clip_id: clipId, status: "pending")).select().execute().value
        return rows.first!.id
    }

    func fetchAnalysis(analysisId: String) async throws -> Analysis {
        let rows: [Analysis] = try await client.database.from("analysis").select().eq("id", value: analysisId).limit(1).execute().value
        return rows.first!
    }
    
    func fetchClipsWithAnalysis() async throws -> [ClipWithAnalysis] {
        // Simple approach: just fetch clips first, analyses can be empty
        let clips: [Clip] = try await client.database
            .from("clips")
            .select()
            .order("created_at", ascending: false)
            .execute()
            .value
        
        // If no clips, return empty array
        if clips.isEmpty {
            return []
        }
        
        // Try to fetch analyses, but don't fail if this doesn't work
        var analyses: [Analysis] = []
        do {
            analyses = try await client.database
                .from("analysis")
                .select()
                .execute()
                .value
        } catch {
            print("Warning: Could not fetch analyses: \(error)")
        }
        
        // Create a dictionary for quick lookup of analysis by clip_id
        let analysisDict = Dictionary(grouping: analyses, by: { $0.clip_id })
        
        // Combine clips with their analyses
        return clips.map { clip in
            let analysis = analysisDict[clip.id]?.first
            return ClipWithAnalysis(
                id: clip.id,
                storage_key: clip.storage_key,
                duration_s: clip.duration_s,
                created_at: clip.created_at,
                analysis_id: analysis?.id,
                analysis_status: analysis?.status,
                shot_type: analysis?.shot_type,
                result: analysis?.result,
                confidence: analysis?.confidence,
                tips_text: analysis?.tips_text,
                error_msg: analysis?.error_msg,
                analysis_created_at: analysis?.created_at,
                started_at: analysis?.started_at,
                completed_at: analysis?.completed_at
            )
        }
    }
    
    func fetchClipsWithAnalysis(shotType: String? = nil, result: String? = nil, limit: Int = 50) async throws -> [ClipWithAnalysis] {
        // For filtering, we'll fetch all clips and filter in-memory
        // This is simpler than complex nested queries with the current SDK
        let allClips = try await fetchClipsWithAnalysis()
        
        var filteredClips = allClips
        
        if let shotType = shotType {
            // Filter by effective shot type (considering overrides)
            filteredClips = filteredClips.filter { $0.effectiveShotType == shotType }
        }
        
        if let result = result {
            // Filter by effective result (considering overrides)
            filteredClips = filteredClips.filter { $0.effectiveResult == result }
        }
        
        return Array(filteredClips.prefix(limit))
    }
    
    // MARK: - Override Methods
    
    func updateAnalysisOverride(analysisId: String, fieldName: String, overrideValue: String, originalValue: String?) async throws {
        print("🔧 DatabaseService: updateAnalysisOverride called")
        print("🔧 Analysis ID: \(analysisId)")
        print("🔧 Field: \(fieldName)")
        print("🔧 Override Value: \(overrideValue)")
        print("🔧 Original Value: \(originalValue ?? "nil")")
        
        struct OverrideRequest: Encodable {
            let analysis_id: String
            let field_name: String
            let override_value: String
            let original_value: String?
        }
        
        let request = OverrideRequest(
            analysis_id: analysisId,
            field_name: fieldName,
            override_value: overrideValue,
            original_value: originalValue
        )
        
        print("🔧 Calling Supabase function 'update-analysis-overrides'...")
        
        // Call our custom edge function for handling overrides
        do {
            try await client.functions
                .invoke("update-analysis-overrides", options: FunctionInvokeOptions(
                    headers: ["Content-Type": "application/json"],
                    body: JSONEncoder().encode(request)
                ))
            
            print("🔧 Supabase function call completed successfully")
            
        } catch {
            print("❌ Supabase function call failed: \(error)")
            print("❌ Error type: \(type(of: error))")
            throw error
        }
    }
    
    func fetchAnalysisOverrides(analysisIds: [String]) async throws -> [AnalysisOverride] {
        guard !analysisIds.isEmpty else { return [] }
        
        let overrides: [AnalysisOverride] = try await client.database
            .from("analysis_overrides")
            .select()
            .in("analysis_id", values: analysisIds)
            .execute()
            .value
        
        return overrides
    }
    
    func fetchClipsWithAnalysisAndOverrides() async throws -> [ClipWithAnalysis] {
        // First get clips with analysis
        var clipsWithAnalysis = try await fetchClipsWithAnalysis()
        
        // Get all analysis IDs that have completed successfully
        let analysisIds = clipsWithAnalysis.compactMap { clip in
            clip.isComplete ? clip.analysis_id : nil
        }
        
        // Fetch overrides for these analyses
        let overrides = try await fetchAnalysisOverrides(analysisIds: analysisIds)
        
        // Group overrides by analysis_id for efficient lookup
        let overridesByAnalysisId = Dictionary(grouping: overrides, by: { $0.analysis_id })
        
        // Attach overrides to clips
        for i in 0..<clipsWithAnalysis.count {
            let analysisId = clipsWithAnalysis[i].analysis_id
            clipsWithAnalysis[i].overrides = overridesByAnalysisId[analysisId ?? ""] ?? []
        }
        
        return clipsWithAnalysis
    }
}
