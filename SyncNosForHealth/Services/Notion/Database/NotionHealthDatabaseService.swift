import Foundation
import os

struct NotionHealthDatabaseHandle: Sendable {
    let id: String
    let titlePropertyName: String
}

final class NotionHealthDatabaseService {
    private let api = NotionAPIClient()

    func ensureDatabase(parentPageId: String, overrideId: String?, traceId: UUID? = nil) async throws -> NotionHealthDatabaseHandle {
        let trace = traceId?.uuidString ?? "-"
        let overrideIdText = overrideId ?? "-"
        AppLog.notionDatabase.info("ensureDatabase start trace=\(trace, privacy: .public) parentPageId=\(parentPageId, privacy: .private(mask: .hash)) overrideId=\(overrideIdText, privacy: .private(mask: .hash))")
        if let overrideId, !overrideId.isEmpty {
            let handle = try await ensureSchema(databaseId: overrideId, traceId: traceId)
            AppLog.notionDatabase.info("ensureDatabase using override trace=\(trace, privacy: .public) databaseId=\(handle.id, privacy: .private(mask: .hash)) titleProperty=\(handle.titlePropertyName, privacy: .public)")
            return handle
        }

        if let existing = try await findExistingDatabase(parentPageId: parentPageId, traceId: traceId) {
            let handle = try await ensureSchema(databaseId: existing, traceId: traceId)
            AppLog.notionDatabase.info("ensureDatabase found existing trace=\(trace, privacy: .public) databaseId=\(handle.id, privacy: .private(mask: .hash)) titleProperty=\(handle.titlePropertyName, privacy: .public)")
            return handle
        }

        let createdId = try await createDatabase(parentPageId: parentPageId, traceId: traceId)
        let handle = try await ensureSchema(databaseId: createdId, traceId: traceId)
        AppLog.notionDatabase.info("ensureDatabase created trace=\(trace, privacy: .public) databaseId=\(handle.id, privacy: .private(mask: .hash)) titleProperty=\(handle.titlePropertyName, privacy: .public)")
        return handle
    }

    private func findExistingDatabase(parentPageId: String, traceId: UUID?) async throws -> String? {
        let body: [String: Any] = [
            "filter": ["property": "object", "value": "database"],
            "query": NotionHealthDatabaseSpec.title,
            "page_size": 50,
        ]

        let data = try await api.performRequest(method: "POST", path: "/search", body: body, traceId: traceId)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else {
            let trace = traceId?.uuidString ?? "-"
            AppLog.notionDatabase.notice("findExistingDatabase parse failed trace=\(trace, privacy: .public)")
            return nil
        }

        let trace = traceId?.uuidString ?? "-"
        AppLog.notionDatabase.info("findExistingDatabase candidates=\(results.count, privacy: .public) trace=\(trace, privacy: .public) parentPageId=\(parentPageId, privacy: .private(mask: .hash))")
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
                    AppLog.notionDatabase.info("findExistingDatabase matched trace=\(trace, privacy: .public) databaseId=\(id, privacy: .private(mask: .hash))")
                    return id
                }
            }
        }

        AppLog.notionDatabase.info("findExistingDatabase no match trace=\(trace, privacy: .public)")
        return nil
    }

    private func createDatabase(parentPageId: String, traceId: UUID?) async throws -> String {
        let body: [String: Any] = [
            "parent": ["type": "page_id", "page_id": parentPageId],
            "title": [["type": "text", "text": ["content": NotionHealthDatabaseSpec.title]]],
            "properties": NotionHealthDatabaseSpec.properties,
        ]

        let data = try await api.performRequest(method: "POST", path: "/databases", body: body, traceId: traceId)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["id"] as? String else {
            throw NSError(domain: "NotionHealthDatabaseService", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to create database"])
        }
        let url = json["url"] as? String
        let trace = traceId?.uuidString ?? "-"
        let urlText = url ?? "-"
        AppLog.notionDatabase.info("createDatabase ok trace=\(trace, privacy: .public) databaseId=\(id, privacy: .private(mask: .hash)) url=\(urlText, privacy: .public)")
        return id
    }

    private func ensureSchema(databaseId: String, traceId: UUID?) async throws -> NotionHealthDatabaseHandle {
        let data = try await api.performRequest(method: "GET", path: "/databases/\(databaseId)", traceId: traceId)
        var info = try parseAndValidateDatabase(data: data, allowMissingTotalSleep: true)
        let trace = traceId?.uuidString ?? "-"
        AppLog.notionDatabase.info("ensureSchema fetched trace=\(trace, privacy: .public) databaseId=\(databaseId, privacy: .private(mask: .hash)) titleProperty=\(info.titlePropertyName, privacy: .public) hasTotal=\(info.hasTotalSleepMin, privacy: .public)")

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
                _ = try await api.performRequest(method: "PATCH", path: "/databases/\(databaseId)", body: renameBody, traceId: traceId)
                info = DatabaseSchemaInfo(titlePropertyName: "Date", hasTotalSleepMin: info.hasTotalSleepMin)
                AppLog.notionDatabase.info("ensureSchema renamed title Name→Date trace=\(trace, privacy: .public) databaseId=\(databaseId, privacy: .private(mask: .hash))")
            } catch {
                AppLog.notionDatabase.notice("ensureSchema rename failed trace=\(trace, privacy: .public) databaseId=\(databaseId, privacy: .private(mask: .hash)) error=\(String(describing: error), privacy: .public)")
                // fallback：继续使用原 title 属性名（通常为 "Name"）
            }
        }

        if !info.hasTotalSleepMin {
            let body: [String: Any] = [
                "properties": [
                    "TotalSleepMin": ["number": ["format": "number"]],
                ]
            ]
            _ = try await api.performRequest(method: "PATCH", path: "/databases/\(databaseId)", body: body, traceId: traceId)
            info = DatabaseSchemaInfo(titlePropertyName: info.titlePropertyName, hasTotalSleepMin: true)
            AppLog.notionDatabase.info("ensureSchema added TotalSleepMin trace=\(trace, privacy: .public) databaseId=\(databaseId, privacy: .private(mask: .hash))")
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
