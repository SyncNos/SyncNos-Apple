import Foundation

struct NotionError: Error, LocalizedError {
    let status: Int
    let code: String?
    let message: String?
    let requestId: String?

    var errorDescription: String? {
        if let message { return "Notion API error \(status): \(message)" }
        return "Notion API error \(status)"
    }

    static func from(data: Data, statusCode: Int) -> NotionError {
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return NotionError(
            status: statusCode,
            code: json?["code"] as? String,
            message: json?["message"] as? String,
            requestId: json?["request_id"] as? String
        )
    }
}
