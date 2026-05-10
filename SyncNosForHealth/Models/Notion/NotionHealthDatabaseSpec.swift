import Foundation

enum NotionHealthDatabaseSpec {
    static let title = "SyncNos-Health"

    static var properties: [String: Any] {
        [
            "Date": ["title": [:]],
            "TotalSleepMin": ["number": ["format": "number"]],
        ]
    }
}
