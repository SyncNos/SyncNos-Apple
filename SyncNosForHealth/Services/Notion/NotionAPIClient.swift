import Foundation

final class NotionAPIClient {
    private let apiBase = "https://api.notion.com/v1"
    private let notionVersion = "2022-06-28"
    private let maxRetries = 4
    private let baseBackoffMs: UInt64 = 500_000_000

    func performRequest(
        method: String,
        path: String,
        body: [String: Any]? = nil
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
            let (data, response): (Data, URLResponse)
            do {
                (data, response) = try await URLSession.shared.data(for: request)
            } catch {
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
                return data
            }

            throw NotionError.from(data: data, statusCode: httpResponse.statusCode)
        }

        throw lastError ?? NSError(domain: "NotionAPIClient", code: -4,
                                   userInfo: [NSLocalizedDescriptionKey: "Request failed after retries"])
    }

    private func backoff(attempt: Int) async throws {
        let delay = baseBackoffMs * UInt64(1 << attempt)
        try await Task.sleep(nanoseconds: delay)
    }
}
