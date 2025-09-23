import Foundation
import Supabase

final class SupabaseClientProvider {
    static let shared = SupabaseClientProvider()

    let client: SupabaseClient

    private init() {
        let urlString = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String
        let anon = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String

        guard let urlStr = urlString, !urlStr.isEmpty, let url = URL(string: urlStr) else {
            fatalError("Missing or invalid SUPABASE_URL. Set it in Config.xcconfig or the target's Info.")
        }
        guard let anonKey = anon, !anonKey.isEmpty else {
            fatalError("Missing SUPABASE_ANON_KEY. Set it in Config.xcconfig or the target's Info.")
        }
        self.client = SupabaseClient(supabaseURL: url, supabaseKey: anonKey)
    }
}
