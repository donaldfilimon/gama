import Foundation
import Observation
import SwiftData
import SwiftUI
import WebKit

struct BrowserTab: Identifiable, Hashable, Sendable {
    let id: UUID
    var title: String
    var urlString: String
    var isLoading: Bool

    init(
        id: UUID = UUID(),
        title: String = "New Tab",
        urlString: String = "about:home",
        isLoading: Bool = false
    ) {
        self.id = id
        self.title = title
        self.urlString = urlString
        self.isLoading = isLoading
    }
}

struct SidebarLink: Identifiable, Hashable, Sendable {
    let id: UUID
    var title: String
    var urlString: String
    var symbol: String

    init(id: UUID = UUID(), title: String, urlString: String, symbol: String) {
        self.id = id
        self.title = title
        self.urlString = urlString
        self.symbol = symbol
    }
}

@MainActor
@Observable
final class BrowserSession {
    var tabs: [BrowserTab] = []
    var selectedTabID: BrowserTab.ID = UUID()
    var sidebarSelection: SidebarLink.ID?
    var status: String = "Ready"
    var addressField: String = "about:home"
    var isResolvingQuery: Bool = false
    var showQtPanel: Bool = true {
        didSet { persistSettings() }
    }
    var columnVisibility: NavigationSplitViewVisibility = .all

    /// Live WKWebViews keyed by tab id (UI-only; not observed).
    @ObservationIgnored
    var webViews: [BrowserTab.ID: WKWebView] = [:]

    @ObservationIgnored
    private let modelContext: ModelContext

    let favorites: [SidebarLink] = [
        SidebarLink(title: "Home", urlString: "about:home", symbol: "house.fill"),
        SidebarLink(title: "Apple", urlString: "https://www.apple.com", symbol: "apple.logo"),
        SidebarLink(title: "Swift.org", urlString: "https://www.swift.org", symbol: "swift"),
        SidebarLink(title: "Qt Docs", urlString: "https://doc.qt.io", symbol: "book.closed.fill"),
    ]

    var recents: [SidebarLink] = []

    var selectedTab: BrowserTab? {
        tabs.first { $0.id == selectedTabID }
    }

    var selectedWebView: WKWebView? {
        webViews[selectedTabID]
    }

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        hydrate()
    }

    func selectTab(_ id: BrowserTab.ID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        selectedTabID = id
        if let tab = tabs.first(where: { $0.id == id }) {
            addressField = tab.urlString
        }
        persistTabs()
    }

    func newTab(url: String = "about:home") {
        let tab = BrowserTab(urlString: url)
        tabs.append(tab)
        selectedTabID = tab.id
        addressField = url
        persistTabs()
    }

    func closeTab(_ id: BrowserTab.ID) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }

        // Sole tab: reset in place (keep id) so the WKWebView stays attached.
        if tabs.count == 1 {
            var tab = tabs[idx]
            tab.title = "New Tab"
            tab.urlString = "about:home"
            tab.isLoading = false
            tabs[idx] = tab
            selectedTabID = tab.id
            addressField = "about:home"
            if let webView = webViews[id] {
                WebPageView.load("about:home", into: webView) { [weak self] message in
                    self?.publishStatus(message, for: id)
                }
            }
            persistTabs()
            return
        }

        webViews.removeValue(forKey: id)?.stopLoading()
        tabs.remove(at: idx)
        if selectedTabID == id {
            let next = tabs[min(idx, tabs.count - 1)]
            selectedTabID = next.id
            addressField = next.urlString
        }
        persistTabs()
    }

    func closeSelectedTab() {
        closeTab(selectedTabID)
    }

    func selectRelativeTab(offset: Int) {
        guard let idx = tabs.firstIndex(where: { $0.id == selectedTabID }), !tabs.isEmpty else { return }
        let next = (idx + offset + tabs.count) % tabs.count
        selectTab(tabs[next].id)
    }

    func updateSelectedURL(_ url: String, title: String? = nil) {
        updateURL(url, for: selectedTabID, title: title)
    }

    /// Update a specific tab's URL. Only syncs the address field / recents when selected.
    func updateURL(_ url: String, for tabID: BrowserTab.ID, title: String? = nil) {
        guard let idx = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        var tab = tabs[idx]
        tab.urlString = url
        if let title, !title.isEmpty {
            tab.title = title
        } else if let host = URL(string: url)?.host, !host.isEmpty {
            tab.title = host
        }
        tabs[idx] = tab
        guard tabID == selectedTabID else {
            persistTabs()
            return
        }
        addressField = url
        pushRecent(title: tab.title, url: url)
        persistTabs()
    }

    func setTitle(_ title: String, for tabID: BrowserTab.ID) {
        guard let idx = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        var tab = tabs[idx]
        guard tab.title != title else { return }
        tab.title = title
        tabs[idx] = tab
        persistTabs()
    }

    func setLoading(_ loading: Bool, for tabID: BrowserTab.ID) {
        guard let idx = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        var tab = tabs[idx]
        guard tab.isLoading != loading else { return }
        tab.isLoading = loading
        tabs[idx] = tab
    }

    func publishStatus(_ message: String, for tabID: BrowserTab.ID) {
        guard tabID == selectedTabID else { return }
        status = message
        GamaQt.setPanelStatus(message)
    }

    func openSidebarLink(_ link: SidebarLink) {
        sidebarSelection = link.id
        addressField = link.urlString
        navigateActive(to: link.urlString)
    }

    func navigateActive(to raw: String) {
        guard let webView = selectedWebView else {
            updateSelectedURL(raw)
            return
        }
        WebPageView.load(raw, into: webView) { [weak self] message in
            Task { @MainActor in
                guard let self else { return }
                self.publishStatus(message, for: self.selectedTabID)
            }
        }
        updateSelectedURL(raw)
    }

    func goHome() {
        addressField = "about:home"
        navigateActive(to: "about:home")
    }

    func goBack() { selectedWebView?.goBack() }
    func goForward() { selectedWebView?.goForward() }
    func reload() { selectedWebView?.reload() }

    func summarizeActiveTab() async {
        guard let tab = selectedTab else { return }
        status = "CoreAI summarizing…"
        await SmartSearchService.shared.summarizePage(title: tab.title, url: tab.urlString)
        let insight = SmartSearchService.shared.pageInsight
        if !insight.isEmpty {
            status = insight
            GamaQt.setPanelStatus(insight)
        }
    }

    // MARK: - SwiftData

    private func hydrate() {
        loadSettings()
        loadRecents()
        loadTabs()
        if tabs.isEmpty {
            let first = BrowserTab()
            tabs = [first]
            selectedTabID = first.id
            addressField = first.urlString
            persistTabs()
        }
    }

    private func loadTabs() {
        var descriptor = FetchDescriptor<PersistedTab>(
            sortBy: [SortDescriptor(\.sortIndex)]
        )
        descriptor.fetchLimit = 32
        let rows = (try? modelContext.fetch(descriptor)) ?? []
        guard !rows.isEmpty else { return }

        tabs = rows.map {
            BrowserTab(id: $0.tabID, title: $0.title, urlString: $0.urlString, isLoading: false)
        }
        if let selected = rows.first(where: \.isSelected)?.tabID,
           tabs.contains(where: { $0.id == selected }) {
            selectedTabID = selected
        } else if let first = tabs.first {
            selectedTabID = first.id
        }
        addressField = selectedTab?.urlString ?? "about:home"
    }

    private func loadRecents() {
        var descriptor = FetchDescriptor<PersistedRecent>(
            sortBy: [SortDescriptor(\.visitedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 12
        let rows = (try? modelContext.fetch(descriptor)) ?? []
        recents = rows.map {
            SidebarLink(title: $0.title, urlString: $0.urlString, symbol: "clock")
        }
    }

    private func loadSettings() {
        let descriptor = FetchDescriptor<BrowserSettings>()
        if let settings = try? modelContext.fetch(descriptor).first {
            showQtPanel = settings.showQtPanel
        } else {
            modelContext.insert(BrowserSettings(showQtPanel: showQtPanel))
            try? modelContext.save()
        }
    }

    private func persistTabs() {
        let existing = (try? modelContext.fetch(FetchDescriptor<PersistedTab>())) ?? []
        let keep = Set(tabs.map(\.id))
        for row in existing where !keep.contains(row.tabID) {
            modelContext.delete(row)
        }
        let byID = Dictionary(uniqueKeysWithValues: existing.map { ($0.tabID, $0) })
        for (index, tab) in tabs.enumerated() {
            if let row = byID[tab.id] {
                row.title = tab.title
                row.urlString = tab.urlString
                row.sortIndex = index
                row.isSelected = tab.id == selectedTabID
                row.updatedAt = .now
            } else {
                modelContext.insert(
                    PersistedTab(
                        tabID: tab.id,
                        title: tab.title,
                        urlString: tab.urlString,
                        sortIndex: index,
                        isSelected: tab.id == selectedTabID
                    )
                )
            }
        }
        try? modelContext.save()
    }

    private func persistSettings() {
        let descriptor = FetchDescriptor<BrowserSettings>()
        if let settings = try? modelContext.fetch(descriptor).first {
            settings.showQtPanel = showQtPanel
            settings.updatedAt = .now
        } else {
            modelContext.insert(BrowserSettings(showQtPanel: showQtPanel))
        }
        try? modelContext.save()
    }

    private func pushRecent(title: String, url: String) {
        guard url != "about:home", !url.isEmpty else { return }

        let descriptor = FetchDescriptor<PersistedRecent>(
            predicate: #Predicate { $0.urlString == url }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.title = title
            existing.visitedAt = .now
        } else {
            modelContext.insert(PersistedRecent(urlString: url, title: title))
        }

        // Cap recents at 12.
        let all = FetchDescriptor<PersistedRecent>(
            sortBy: [SortDescriptor(\.visitedAt, order: .reverse)]
        )
        if let rows = try? modelContext.fetch(all), rows.count > 12 {
            for stale in rows.dropFirst(12) {
                modelContext.delete(stale)
            }
        }
        try? modelContext.save()
        loadRecents()
    }
}
