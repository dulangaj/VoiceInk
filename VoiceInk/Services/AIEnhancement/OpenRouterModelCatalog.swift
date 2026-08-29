import Foundation

/// OpenRouter model metadata beyond the plain id list that `OpenRouterClient` returns.
///
/// Dictation cleanup gains nothing from thinking tokens but pays their latency, so
/// reasoning is switched off per request. Models flagged `reasoning.mandatory` reject
/// `effort: "none"`, so the catalog remembers which ones they are.
enum OpenRouterModelCatalog {
    private static let modelsURL = URL(string: "https://openrouter.ai/api/v1/models")!
    private static let mandatoryReasoningKey = "openRouterMandatoryReasoningModels"

    struct Catalog {
        let modelIDs: [String]
        let mandatoryReasoningIDs: [String]
    }

    static func fetch(timeout: TimeInterval = 15) async throws -> Catalog {
        var request = URLRequest(url: modelsURL)
        request.timeoutInterval = timeout

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let models = json["data"] as? [[String: Any]]
        else {
            throw EnhancementError.customError("Unexpected response format from OpenRouter models endpoint.")
        }

        let identified = models.compactMap { model -> (id: String, mandatory: Bool)? in
            guard let id = model["id"] as? String else { return nil }
            let reasoning = model["reasoning"] as? [String: Any]
            return (id, reasoning?["mandatory"] as? Bool ?? false)
        }

        return Catalog(
            modelIDs: identified.map(\.id).sorted(),
            mandatoryReasoningIDs: identified.filter(\.mandatory).map(\.id)
        )
    }

    static func saveMandatoryReasoningIDs(_ ids: [String], in defaults: UserDefaults = .standard) {
        defaults.set(ids, forKey: mandatoryReasoningKey)
    }

    /// An unfetched catalog assumes reasoning is mandatory: sending "none" to a model
    /// that requires reasoning is rejected, while "minimal" is accepted either way.
    static func requiresReasoning(_ modelName: String, in defaults: UserDefaults = .standard) -> Bool {
        guard let ids = defaults.array(forKey: mandatoryReasoningKey) as? [String] else { return true }
        return ids.contains(modelName)
    }
}
