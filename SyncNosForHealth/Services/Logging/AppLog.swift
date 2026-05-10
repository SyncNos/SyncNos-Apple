import Foundation
import os

enum AppLog {
    static let subsystem = Bundle.main.bundleIdentifier ?? "SyncNosForHealth"

    static let ui = Logger(subsystem: subsystem, category: "UI")
    static let notion = Logger(subsystem: subsystem, category: "Notion")
    static let notionAPI = Logger(subsystem: subsystem, category: "Notion.API")
    static let notionDatabase = Logger(subsystem: subsystem, category: "Notion.Database")
    static let notionSync = Logger(subsystem: subsystem, category: "Notion.Sync")
}

