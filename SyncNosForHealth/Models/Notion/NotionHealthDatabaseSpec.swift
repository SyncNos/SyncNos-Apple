import Foundation

enum NotionHealthDatabaseSpec {
    static let title = "SyncNos-Health"
    static let datePropertyName = "Date"

    static var properties: [String: Any] {
        [
            // Notion 数据库必须有且仅有一个 title 属性；date 必须是独立的 date 属性。
            "Title": ["title": [:]],
            datePropertyName: ["date": [:]],
            "TotalSleepMin": ["number": ["format": "number"]],
        ]
    }
}
