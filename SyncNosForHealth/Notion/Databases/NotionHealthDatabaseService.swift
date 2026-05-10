import Foundation

final class NotionHealthDatabaseService {
    private let api = NotionAPIClient()

    func ensureDatabase(parentPageId: String, overrideId: String?) async throws -> String {
        if let overrideId, !overrideId.isEmpty {
            try await validateDatabase(id: overrideId)
            return overrideId
        }

        if let existing = try await findExistingDatabase(parentPageId: parentPageId) {
            return existing
        }

        return try await createDatabase(parentPageId: parentPageId)
    }

    private func validateDatabase(id: String) async throws {
        _ = try await api.performRequest(method: "GET", path: "/databases/\(id)")
    }

    private func findExistingDatabase(parentPageId: String) async throws -> String? {
        let body: [String: Any] = [
            "filter": ["property": "object", "value": "database"],
            "query": NotionHealthDatabaseSpec.title,
            "page_size": 50,
        ]

        let data = try await api.performRequest(method: "POST", path: "/search", body: body)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else {
            return nil
        }

        for r in results {
            guard r["object"] as? String == "database" else { continue }
            guard let id = r["id"] as? String else { continue }

            let archived = r["archived"] as? Bool ?? false
            let inTrash = r["in_trash"] as? Bool ?? false
            if archived || inTrash { continue }

            if let parent = r["parent"] as? [String: Any],
               let pageId = parent["page_id"] as? String {
                let normalized1 = pageId.replacingOccurrences(of: "-", with: "").lowercased()
                let normalized2 = parentPageId.replacingOccurrences(of: "-", with: "").lowercased()
                if normalized1 == normalized2 {
                    return id
                }
            }
        }

        return nil
    }

    private func createDatabase(parentPageId: String) async throws -> String {
        let body: [String: Any] = [
            "parent": ["type": "page_id", "page_id": parentPageId],
            "title": [["type": "text", "text": ["content": NotionHealthDatabaseSpec.title]]],
            "properties": NotionHealthDatabaseSpec.properties,
        ]

        let data = try await api.performRequest(method: "POST", path: "/databases", body: body)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["id"] as? String else {
            throw NSError(domain: "NotionHealthDatabaseService", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to create database"])
        }
        return id
    }
}
