import Foundation

final class NotionHealthDailyUpsertService {
    private let api = NotionAPIClient()

    func upsert(databaseId: String, titlePropertyName: String, date: String, totalSleepMin: Int) async throws {
        let existingPageId = try await findPage(databaseId: databaseId, titlePropertyName: titlePropertyName, date: date)

        if let pageId = existingPageId {
            try await updatePage(pageId: pageId, totalSleepMin: totalSleepMin)
        } else {
            try await createPage(databaseId: databaseId, titlePropertyName: titlePropertyName, date: date, totalSleepMin: totalSleepMin)
        }
    }

    private func findPage(databaseId: String, titlePropertyName: String, date: String) async throws -> String? {
        let body: [String: Any] = [
            "filter": [
                "property": titlePropertyName,
                "title": ["equals": date],
            ]
        ]

        let data = try await api.performRequest(method: "POST", path: "/databases/\(databaseId)/query", body: body)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else {
            return nil
        }

        if results.count > 1 {
            throw NSError(domain: "NotionHealthDailyUpsertService", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Multiple pages found for date \(date)"])
        }

        return results.first?["id"] as? String
    }

    private func createPage(databaseId: String, titlePropertyName: String, date: String, totalSleepMin: Int) async throws {
        let body: [String: Any] = [
            "parent": ["database_id": databaseId],
            "properties": [
                titlePropertyName: [
                    "title": [["text": ["content": date]]]
                ],
                "TotalSleepMin": [
                    "number": totalSleepMin
                ],
            ]
        ]

        _ = try await api.performRequest(method: "POST", path: "/pages", body: body)
    }

    private func updatePage(pageId: String, totalSleepMin: Int) async throws {
        let body: [String: Any] = [
            "properties": [
                "TotalSleepMin": [
                    "number": totalSleepMin
                ],
            ]
        ]

        _ = try await api.performRequest(method: "PATCH", path: "/pages/\(pageId)", body: body)
    }
}
