import Foundation

struct NotionPageSummary: Identifiable, Hashable {
    let id: String
    let title: String
}

final class NotionParentPagesService {
    private let api = NotionAPIClient()

    func listParentPages(savedPageId: String?) async throws -> [NotionPageSummary] {
        var collected: [NotionPageSummary] = []
        var seen = Set<String>()
        var startCursor: String?

        repeat {
            var body: [String: Any] = [
                "filter": ["property": "object", "value": "page"],
                "page_size": 50,
            ]
            if let cursor = startCursor {
                body["start_cursor"] = cursor
            }

            let data = try await api.performRequest(method: "POST", path: "/search", body: body)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [[String: Any]] else {
                break
            }

            for r in results {
                guard r["object"] as? String == "page" else { continue }
                guard let id = r["id"] as? String else { continue }

                let archived = r["archived"] as? Bool ?? false
                let inTrash = r["in_trash"] as? Bool ?? false
                if archived || inTrash { continue }

                if let parent = r["parent"] as? [String: Any],
                   parent["database_id"] != nil {
                    continue
                }

                let normalizedId = id.replacingOccurrences(of: "-", with: "").lowercased()
                if seen.contains(normalizedId) { continue }
                seen.insert(normalizedId)

                let title = extractTitle(from: r)
                collected.append(NotionPageSummary(id: id, title: title))
            }

            let hasMore = json["has_more"] as? Bool ?? false
            startCursor = hasMore ? (json["next_cursor"] as? String) : nil
        } while startCursor != nil

        if let savedId = savedPageId,
           !collected.contains(where: { $0.id == savedId }) {
            if let resolved = try? await resolvePage(id: savedId) {
                collected.insert(resolved, at: 0)
            }
        }

        return collected
    }

    private func resolvePage(id: String) async throws -> NotionPageSummary? {
        let data = try await api.performRequest(method: "GET", path: "/pages/\(id)")
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let archived = json["archived"] as? Bool ?? false
        let inTrash = json["in_trash"] as? Bool ?? false
        if archived || inTrash { return nil }

        return NotionPageSummary(id: id, title: extractTitle(from: json))
    }

    private func extractTitle(from page: [String: Any]) -> String {
        guard let properties = page["properties"] as? [String: Any],
              let titleProp = properties["title"] as? [String: Any],
              let titleArray = titleProp["title"] as? [[String: Any]],
              let first = titleArray.first,
              let plainText = first["plain_text"] as? String else {
            return "Untitled"
        }
        return plainText
    }
}
