import Foundation

struct NotionHealthDatabaseHandle: Sendable {
    let id: String
    let titlePropertyName: String
}

final class NotionHealthDatabaseService {
    private let api = NotionAPIClient()

    func ensureDatabase(parentPageId: String, overrideId: String?) async throws -> NotionHealthDatabaseHandle {
        if let overrideId, !overrideId.isEmpty {
            return try await ensureSchema(databaseId: overrideId)
        }

        if let existing = try await findExistingDatabase(parentPageId: parentPageId) {
            return try await ensureSchema(databaseId: existing)
        }

        let createdId = try await createDatabase(parentPageId: parentPageId)
        return try await ensureSchema(databaseId: createdId)
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

    private func ensureSchema(databaseId: String) async throws -> NotionHealthDatabaseHandle {
        let data = try await api.performRequest(method: "GET", path: "/databases/\(databaseId)")
        var info = try parseAndValidateDatabase(data: data, allowMissingTotalSleep: true)

        // 兼容旧/手工数据库：Notion 默认 title 属性名通常是 "Name"。
        // App 约定 title 属性名为 "Date"（承载 yyyy-MM-dd），因此若发现为 "Name"，尝试 rename 为 "Date"。
        if info.titlePropertyName != "Date", info.titlePropertyName == "Name" {
            let renameBody: [String: Any] = [
                "properties": [
                    "Name": [
                        "name": "Date"
                    ]
                ]
            ]
            // rename 失败不应阻断同步：可能存在同名属性冲突或权限限制。
            do {
                _ = try await api.performRequest(method: "PATCH", path: "/databases/\(databaseId)", body: renameBody)
                info = DatabaseSchemaInfo(titlePropertyName: "Date", hasTotalSleepMin: info.hasTotalSleepMin)
            } catch {
                // fallback：继续使用原 title 属性名（通常为 "Name"）
            }
        }

        if !info.hasTotalSleepMin {
            let body: [String: Any] = [
                "properties": [
                    "TotalSleepMin": ["number": ["format": "number"]],
                ]
            ]
            _ = try await api.performRequest(method: "PATCH", path: "/databases/\(databaseId)", body: body)
            info = DatabaseSchemaInfo(titlePropertyName: info.titlePropertyName, hasTotalSleepMin: true)
        }

        return NotionHealthDatabaseHandle(id: databaseId, titlePropertyName: info.titlePropertyName)
    }

    private struct DatabaseSchemaInfo {
        let titlePropertyName: String
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

        return DatabaseSchemaInfo(titlePropertyName: titleName, hasTotalSleepMin: hasTotal)
    }
}
