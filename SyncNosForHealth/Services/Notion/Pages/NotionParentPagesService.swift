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

        // 与 macOS 保持一致：不要全量枚举 workspace 的所有页面。
        // 逐页请求，一旦某一页能筛出可用的 parent pages 就立即返回；
        // 只有当“这一页全部被过滤掉”时才继续翻页。
        var startCursor: String? = nil
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

            var addedThisPage = 0
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

                collected.append(NotionPageSummary(id: id, title: extractTitle(from: r)))
                addedThisPage += 1
            }

            if addedThisPage > 0 {
                break
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

        if let parent = json["parent"] as? [String: Any],
           parent["database_id"] != nil {
            return nil
        }

        return NotionPageSummary(id: id, title: extractTitle(from: json))
    }

    private func extractTitle(from page: [String: Any]) -> String {
        guard let properties = page["properties"] as? [String: Any] else { return "Untitled" }

        // 与 macOS 保持一致：在 properties 中寻找第一个 type == "title" 的属性，聚合其 plain_text。
        for (_, value) in properties {
            guard let dict = value as? [String: Any],
                  let type = dict["type"] as? String,
                  type == "title" else { continue }

            let titleArray = (dict["title"] as? [[String: Any]]) ?? []
            let title = titleArray.compactMap { $0["plain_text"] as? String }.joined()
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Untitled" : trimmed
        }

        return "Untitled"
    }
}
