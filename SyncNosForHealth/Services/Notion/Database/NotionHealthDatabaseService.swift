import Foundation
import os

struct NotionHealthDatabaseHandle: Sendable {
    let id: String
    let titlePropertyName: String
    let datePropertyName: String
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
            let databaseTitle = extractDatabaseTitle(from: r)

            let archived = r["archived"] as? Bool ?? false
            let inTrash = r["in_trash"] as? Bool ?? false
            if archived || inTrash { continue }

            if let parent = r["parent"] as? [String: Any],
               let pageId = parent["page_id"] as? String {
                let normalized1 = pageId.replacingOccurrences(of: "-", with: "").lowercased()
                let normalized2 = parentPageId.replacingOccurrences(of: "-", with: "").lowercased()
                if normalized1 == normalized2 {
                    // Notion /search 的 query 是模糊匹配，可能把“非健康数据库”也搜出来（例如库内页面标题命中 query）。
                    // 为避免误用其它数据库，这里只自动复用 title 精确匹配的健康数据库；否则请用户用 overrideId 显式指定。
                    if let databaseTitle, databaseTitle == NotionHealthDatabaseSpec.title {
                        AppLog.notionDatabase.info("findExistingDatabase matched trace=\(trace, privacy: .public) databaseId=\(id, privacy: .private(mask: .hash)) title=\(databaseTitle, privacy: .public)")
                        return id
                    }
                    let titleText = databaseTitle ?? "-"
                    AppLog.notionDatabase.notice("findExistingDatabase parent matched but title mismatched trace=\(trace, privacy: .public) databaseId=\(id, privacy: .private(mask: .hash)) title=\(titleText, privacy: .public)")
                }
            }
        }

        AppLog.notionDatabase.info("findExistingDatabase no match trace=\(trace, privacy: .public)")
        return nil
    }

    private func extractDatabaseTitle(from database: [String: Any]) -> String? {
        let titleArray = database["title"] as? [[String: Any]] ?? []
        let title = titleArray.compactMap { $0["plain_text"] as? String }.joined()
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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
        let databaseURL = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["url"] as? String
        let info = try parseAndValidateDatabase(data: data)
        let trace = traceId?.uuidString ?? "-"
        let databaseURLText = databaseURL ?? "-"
        let dateTypeText = info.datePropertyType ?? "-"
        AppLog.notionDatabase.info("ensureSchema fetched trace=\(trace, privacy: .public) databaseId=\(databaseId, privacy: .private(mask: .hash)) url=\(databaseURLText, privacy: .public) titleProperty=\(info.titlePropertyName, privacy: .public) hasTotal=\(info.hasTotalSleepMin, privacy: .public) hasDate=\(info.hasDateProperty, privacy: .public) dateType=\(dateTypeText, privacy: .public)")

        guard info.titlePropertyName == NotionHealthDatabaseSpec.titlePropertyName else {
            throw NSError(
                domain: "NotionHealthDatabaseService",
                code: -21,
                userInfo: [NSLocalizedDescriptionKey: "健康数据库 schema 不符合预期：title 属性必须命名为 '\(NotionHealthDatabaseSpec.titlePropertyName)'（当前为 '\(info.titlePropertyName)'）。请使用新的健康数据库，或在设置中用「健康数据库 ID 覆盖」指定正确数据库。"]
            )
        }

        guard info.hasDateProperty, info.datePropertyType == "date" else {
            throw NSError(
                domain: "NotionHealthDatabaseService",
                code: -22,
                userInfo: [NSLocalizedDescriptionKey: "健康数据库 schema 不符合预期：缺少 date 属性 '\(NotionHealthDatabaseSpec.datePropertyName)'（或类型不是 date）。请使用新的健康数据库，或在设置中用「健康数据库 ID 覆盖」指定正确数据库。"]
            )
        }

        guard info.hasTotalSleepMin else {
            throw NSError(
                domain: "NotionHealthDatabaseService",
                code: -23,
                userInfo: [NSLocalizedDescriptionKey: "健康数据库 schema 不符合预期：缺少 number 属性 'TotalSleepMin'。请使用新的健康数据库，或在设置中用「健康数据库 ID 覆盖」指定正确数据库。"]
            )
        }

        return NotionHealthDatabaseHandle(
            id: databaseId,
            titlePropertyName: info.titlePropertyName,
            datePropertyName: NotionHealthDatabaseSpec.datePropertyName
        )
    }

    private struct DatabaseSchemaInfo {
        let titlePropertyName: String
        let hasTotalSleepMin: Bool
        let hasDateProperty: Bool
        let datePropertyType: String?
    }

    private func parseAndValidateDatabase(
        data: Data
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

        let dateProperty = properties[NotionHealthDatabaseSpec.datePropertyName] as? [String: Any]
        let dateType = dateProperty?["type"] as? String
        let hasDate = (dateType == "date")

        return DatabaseSchemaInfo(
            titlePropertyName: titleName,
            hasTotalSleepMin: hasTotal,
            hasDateProperty: hasDate,
            datePropertyType: dateType
        )
    }
}
