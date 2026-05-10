import Foundation

final class NotionHealthDatabaseService {
    private let api = NotionAPIClient()

    func ensureDatabase(parentPageId: String, overrideId: String?) async throws -> String {
        if let overrideId, !overrideId.isEmpty {
            try await ensureSchema(databaseId: overrideId)
            return overrideId
        }

        if let existing = try await findExistingDatabase(parentPageId: parentPageId) {
            try await ensureSchema(databaseId: existing)
            return existing
        }

        return try await createDatabase(parentPageId: parentPageId)
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

    private func ensureSchema(databaseId: String) async throws {
        let data = try await api.performRequest(method: "GET", path: "/databases/\(databaseId)")
        let info = try parseAndValidateDatabase(data: data, allowMissingTotalSleep: true)

        guard !info.hasTotalSleepMin else { return }

        let body: [String: Any] = [
            "properties": [
                "TotalSleepMin": ["number": ["format": "number"]],
            ]
        ]
        _ = try await api.performRequest(method: "PATCH", path: "/databases/\(databaseId)", body: body)
    }

    private struct DatabaseSchemaInfo {
        let hasTotalSleepMin: Bool
    }

    private func parseAndValidateDatabase(
        data: Data,
        allowMissingTotalSleep: Bool = false
    ) throws -> DatabaseSchemaInfo {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let properties = json["properties"] as? [String: Any] else {
            throw NSError(
                domain: "NotionHealthDatabaseService",
                code: -10,
                userInfo: [NSLocalizedDescriptionKey: "Invalid database response"]
            )
        }

        let titlePropertyNames = properties.compactMap { (key, value) -> String? in
            guard let dict = value as? [String: Any],
                  let type = dict["type"] as? String,
                  type == "title" else { return nil }
            return key
        }

        guard let titleName = titlePropertyNames.first else {
            throw NSError(
                domain: "NotionHealthDatabaseService",
                code: -11,
                userInfo: [NSLocalizedDescriptionKey: "Database has no title property"]
            )
        }

        guard titleName == "Date" else {
            throw NSError(
                domain: "NotionHealthDatabaseService",
                code: -12,
                userInfo: [NSLocalizedDescriptionKey: "Database title property is '\(titleName)'; expected 'Date'"]
            )
        }

        var hasTotal = false
        if let total = properties["TotalSleepMin"] as? [String: Any],
           let type = total["type"] as? String {
            if type == "number" {
                hasTotal = true
            } else {
                throw NSError(
                    domain: "NotionHealthDatabaseService",
                    code: -13,
                    userInfo: [NSLocalizedDescriptionKey: "Property 'TotalSleepMin' exists but is not a number"]
                )
            }
        }

        if !allowMissingTotalSleep && !hasTotal {
            throw NSError(
                domain: "NotionHealthDatabaseService",
                code: -14,
                userInfo: [NSLocalizedDescriptionKey: "Database missing required property 'TotalSleepMin'"]
            )
        }

        return DatabaseSchemaInfo(hasTotalSleepMin: hasTotal)
    }
}
