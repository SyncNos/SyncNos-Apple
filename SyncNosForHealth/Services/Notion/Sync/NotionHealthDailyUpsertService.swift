import Foundation
import os

final class NotionHealthDailyUpsertService {
    private let api = NotionAPIClient()

    func upsert(
        databaseId: String,
        titlePropertyName: String,
        datePropertyName: String,
        date: String,
        totalSleepMin: Int,
        traceId: UUID? = nil
    ) async throws {
        let trace = traceId?.uuidString ?? "-"
        AppLog.notionSync.info("upsert start trace=\(trace, privacy: .public) databaseId=\(databaseId, privacy: .private(mask: .hash)) titleProperty=\(titlePropertyName, privacy: .public) dateProperty=\(datePropertyName, privacy: .public) date=\(date, privacy: .public) totalSleepMin=\(totalSleepMin, privacy: .private)")

        let existingPageId = try await findPageByDateProperty(
            databaseId: databaseId,
            datePropertyName: datePropertyName,
            date: date,
            traceId: traceId
        )

        if let pageId = existingPageId {
            try await updatePage(
                pageId: pageId,
                totalSleepMin: totalSleepMin,
                datePropertyName: datePropertyName,
                date: date,
                traceId: traceId
            )
        } else {
            try await createPage(
                databaseId: databaseId,
                titlePropertyName: titlePropertyName,
                datePropertyName: datePropertyName,
                date: date,
                totalSleepMin: totalSleepMin,
                traceId: traceId
            )
        }
        AppLog.notionSync.info("upsert done trace=\(trace, privacy: .public) databaseId=\(databaseId, privacy: .private(mask: .hash)) date=\(date, privacy: .public)")
    }

    private func findPageByDateProperty(databaseId: String, datePropertyName: String, date: String, traceId: UUID?) async throws -> String? {
        let body: [String: Any] = [
            "filter": [
                "property": datePropertyName,
                "date": ["equals": date],
            ]
        ]

        let data = try await api.performRequest(method: "POST", path: "/databases/\(databaseId)/query", body: body, traceId: traceId)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else {
            let trace = traceId?.uuidString ?? "-"
            AppLog.notionSync.notice("findPageByDateProperty parse failed trace=\(trace, privacy: .public) databaseId=\(databaseId, privacy: .private(mask: .hash)) date=\(date, privacy: .public)")
            return nil
        }

        let trace = traceId?.uuidString ?? "-"
        AppLog.notionSync.info("findPageByDateProperty results=\(results.count, privacy: .public) trace=\(trace, privacy: .public) databaseId=\(databaseId, privacy: .private(mask: .hash)) date=\(date, privacy: .public)")
        if results.count > 1 {
            throw NSError(domain: "NotionHealthDailyUpsertService", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "Multiple pages found for date \(date) (date property)"])
        }

        let id = results.first?["id"] as? String
        if let id {
            AppLog.notionSync.info("findPageByDateProperty hit trace=\(trace, privacy: .public) pageId=\(id, privacy: .private(mask: .hash))")
        } else {
            AppLog.notionSync.info("findPageByDateProperty miss trace=\(trace, privacy: .public)")
        }
        return id
    }

    private func createPage(databaseId: String, titlePropertyName: String, datePropertyName: String, date: String, totalSleepMin: Int, traceId: UUID?) async throws {
        let body: [String: Any] = [
            "parent": ["database_id": databaseId],
            "properties": [
                titlePropertyName: [
                    "title": [["text": ["content": date]]]
                ],
                datePropertyName: [
                    "date": ["start": date]
                ],
                "TotalSleepMin": [
                    "number": totalSleepMin
                ],
            ]
        ]

        let data = try await api.performRequest(method: "POST", path: "/pages", body: body, traceId: traceId)
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let pageId = json["id"] as? String
            let url = json["url"] as? String
            let trace = traceId?.uuidString ?? "-"
            let pageIdText = pageId ?? "-"
            let urlText = url ?? "-"
            AppLog.notionSync.info("createPage ok trace=\(trace, privacy: .public) pageId=\(pageIdText, privacy: .private(mask: .hash)) url=\(urlText, privacy: .public)")
        } else {
            let trace = traceId?.uuidString ?? "-"
            AppLog.notionSync.info("createPage ok trace=\(trace, privacy: .public) (unparseable response)")
        }
    }

    private func updatePage(
        pageId: String,
        totalSleepMin: Int,
        datePropertyName: String,
        date: String,
        traceId: UUID?
    ) async throws {
        var properties: [String: Any] = [
            "TotalSleepMin": [
                "number": totalSleepMin
            ]
        ]
        properties[datePropertyName] = ["date": ["start": date]]
        let body: [String: Any] = [
            "properties": properties
        ]

        let data = try await api.performRequest(method: "PATCH", path: "/pages/\(pageId)", body: body, traceId: traceId)
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let url = json["url"] as? String
            let trace = traceId?.uuidString ?? "-"
            let urlText = url ?? "-"
            AppLog.notionSync.info("updatePage ok trace=\(trace, privacy: .public) pageId=\(pageId, privacy: .private(mask: .hash)) url=\(urlText, privacy: .public)")
        } else {
            let trace = traceId?.uuidString ?? "-"
            AppLog.notionSync.info("updatePage ok trace=\(trace, privacy: .public) pageId=\(pageId, privacy: .private(mask: .hash)) (unparseable response)")
        }
    }
}
