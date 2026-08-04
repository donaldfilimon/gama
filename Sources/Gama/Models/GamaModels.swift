import Foundation
import SwiftData

@Model
final class PersistedTab {
    @Attribute(.unique) var tabID: UUID
    var title: String
    var urlString: String
    var sortIndex: Int
    var isSelected: Bool
    var updatedAt: Date

    init(
        tabID: UUID = UUID(),
        title: String = "New Tab",
        urlString: String = "about:home",
        sortIndex: Int = 0,
        isSelected: Bool = false,
        updatedAt: Date = .now
    ) {
        self.tabID = tabID
        self.title = title
        self.urlString = urlString
        self.sortIndex = sortIndex
        self.isSelected = isSelected
        self.updatedAt = updatedAt
    }
}

@Model
final class PersistedRecent {
    @Attribute(.unique) var urlString: String
    var title: String
    var visitedAt: Date

    init(urlString: String, title: String, visitedAt: Date = .now) {
        self.urlString = urlString
        self.title = title
        self.visitedAt = visitedAt
    }
}

@Model
final class BrowserSettings {
    var showQtPanel: Bool
    var updatedAt: Date

    init(showQtPanel: Bool = true, updatedAt: Date = .now) {
        self.showQtPanel = showQtPanel
        self.updatedAt = updatedAt
    }
}
