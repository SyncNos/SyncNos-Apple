import Foundation
import os

final class NotionAPIClient {
    private let apiBase = "https://api.notion.com/v1"
    private let notionVersion = "2022-06-28"
    private let maxRetries = 4
    private let baseBackoffMs: UInt64 = 500_000_000

    func performRequest(
        method: String,
        path: String,
        body: [String: Any]? = nil,
        traceId: UUID? = nil
    ) async throws -> Data {
        guard let token = NotionTokenStore.accessToken else {
            throw NSError(domain: "NotionAPIClient", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No Notion access token"])
        }

        guard let url = URL(string: apiBase + path) else {
            throw NSError(domain: "NotionAPIClient", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid URL path: \(path)"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(notionVersion, forHTTPHeaderField: "Notion-Version")
        request.timeoutInterval = 30

        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        var lastError: Error?
        for attempt in 0..<maxRetries {
            let trace = traceId?.uuidString ?? "-"
            let bodyKeys = body.map { Array($0.keys).sorted().joined(separator: ",") } ?? "-"
            AppLog.notionAPI.info("→ Notion \(method, privacy: .public) \(path, privacy: .public) attempt=\(attempt + 1, privacy: .public)/\(self.maxRetries, privacy: .public) trace=\(trace, privacy: .public) bodyKeys=\(bodyKeys, privacy: .public)")
            let (data, response): (Data, URLResponse)
            do {
                (data, response) = try await URLSession.shared.data(for: request)
            } catch {
                AppLog.notionAPI.error("✖︎ Notion transport error method=\(method, privacy: .public) path=\(path, privacy: .public) trace=\(trace, privacy: .public) error=\(String(describing: error), privacy: .public)")
                lastError = error
                if attempt < maxRetries - 1 {
                    try await backoff(attempt: attempt)
                    continue
                }
                throw error
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                throw NSError(domain: "NotionAPIClient", code: -3,
                              userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP response"])
            }

            if httpResponse.statusCode == 429 || httpResponse.statusCode == 503 {
                AppLog.notionAPI.notice("↻ Notion retryable status=\(httpResponse.statusCode, privacy: .public) method=\(method, privacy: .public) path=\(path, privacy: .public) trace=\(trace, privacy: .public)")
                if attempt < maxRetries - 1 {
                    if let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After"),
                       let seconds = Double(retryAfter) {
                        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                    } else {
                        try await backoff(attempt: attempt)
                    }
                    continue
                }
            }

            if (200...299).contains(httpResponse.statusCode) {
                let requestIdHeader = httpResponse.value(forHTTPHeaderField: "x-notion-request-id")
                    ?? httpResponse.value(forHTTPHeaderField: "X-Notion-Request-Id")
                    ?? httpResponse.value(forHTTPHeaderField: "notion-request-id")
                let requestId = requestIdHeader ?? "-"
                AppLog.notionAPI.info("← Notion status=\(httpResponse.statusCode, privacy: .public) bytes=\(data.count, privacy: .public) trace=\(trace, privacy: .public) requestId=\(requestId, privacy: .public) path=\(path, privacy: .public)")
                return data
            }

            let notionError = NotionError.from(data: data, statusCode: httpResponse.statusCode)
            let code = notionError.code ?? "-"
            let requestId = notionError.requestId ?? "-"
            let message = notionError.message ?? "-"
            AppLog.notionAPI.error("← Notion error status=\(notionError.status, privacy: .public) code=\(code, privacy: .public) requestId=\(requestId, privacy: .public) trace=\(trace, privacy: .public) message=\(message, privacy: .public) path=\(path, privacy: .public)")
            throw notionError
        }

        throw lastError ?? NSError(domain: "NotionAPIClient", code: -4,
                                   userInfo: [NSLocalizedDescriptionKey: "Request failed after retries"])
    }

    private func backoff(attempt: Int) async throws {
        let delay = baseBackoffMs * UInt64(1 << attempt)
        try await Task.sleep(nanoseconds: delay)
    }
}
