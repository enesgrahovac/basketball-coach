import Foundation

final class AnalysisService {
    private let db = DatabaseService()

    func triggerAnalysis(clipId: String, storageKey: String) async throws {
        let urlString = Bundle.main.object(forInfoDictionaryKey: "EDGE_ANALYZE_URL") as? String ?? ""
        guard let url = URL(string: urlString) else { throw NSError(domain: "EdgeURL", code: 0) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let anon = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String, !anon.isEmpty {
            req.setValue("Bearer \(anon)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: ["clip_id": clipId, "storage_key": storageKey])
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "EdgeFunction", code: (resp as? HTTPURLResponse)?.statusCode ?? 500)
        }
    }

    func pollUntilComplete(analysisId: String, fastSeconds: Int = 10) async throws -> Analysis {
        let start = Date()
        while true {
            let a = try await db.fetchAnalysis(analysisId: analysisId)
            if a.status == "success" || a.status == "failed" {
                return a
            }
            let elapsed = Date().timeIntervalSince(start)
            let interval: TimeInterval = elapsed < Double(fastSeconds) ? 1.0 : 2.0
            try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        }
    }
}
