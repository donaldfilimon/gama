import Combine
import SwiftData
import SwiftUI

struct ContentView: View {
    @Bindable var session: BrowserSession
    @FocusState private var addressFocused: Bool

    private let qtTick = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()
    private var coreAI: SmartSearchService { SmartSearchService.shared }

    var body: some View {
        NavigationSplitView(columnVisibility: $session.columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
        } detail: {
            detailColumn
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 980, minHeight: 680)
        .background {
            LiquidGlassBackdrop()
        }
        .onAppear {
            GamaQt.ensureApplication()
            session.status = "Qt \(GamaQt.version()) · \(coreAI.availabilityMessage)"
            GamaQt.setPanelStatus(session.status)
            coreAI.refreshAvailability()
        }
        .onReceive(qtTick) { _ in
            GamaQt.processEvents()
        }
        .focusedSceneValue(\.gamaBrowserSession, session)
        .focusedSceneValue(\.gamaAddressFocus, { addressFocused = true })
    }

    private var sidebar: some View {
        List(selection: $session.sidebarSelection) {
            Section("Favorites") {
                ForEach(session.favorites) { link in
                    Label(link.title, systemImage: link.symbol)
                        .tag(link.id)
                        .accessibilityIdentifier("sidebar.favorite.\(link.title.lowercased())")
                        .onTapGesture { session.openSidebarLink(link) }
                }
            }
            if !session.recents.isEmpty {
                Section("Recents") {
                    ForEach(session.recents) { link in
                        Label(link.title, systemImage: link.symbol)
                            .tag(link.id)
                            .accessibilityIdentifier("sidebar.recent.\(link.id.uuidString)")
                            .onTapGesture { session.openSidebarLink(link) }
                    }
                }
            }
            Section("Session") {
                LabeledContent("Tabs", value: "\(session.tabs.count)")
                LabeledContent("CoreAI", value: coreAI.isAvailable ? "On" : "Off")
                Toggle("Qt Panel", isOn: $session.showQtPanel)
                    .accessibilityIdentifier("sidebar.toggle.qtPanel")
            }
            if !coreAI.pageInsight.isEmpty || !coreAI.pageTopics.isEmpty {
                Section("Page Insight") {
                    if coreAI.isSummarizing {
                        ProgressView("Summarizing…")
                    }
                    if !coreAI.pageInsight.isEmpty {
                        Text(coreAI.pageInsight)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .accessibilityIdentifier("sidebar.pageInsight")
                    }
                    if !coreAI.pageTopics.isEmpty {
                        Text(coreAI.pageTopics.joined(separator: " · "))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Gama")
        .accessibilityIdentifier("sidebar.root")
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !coreAI.lastRationale.isEmpty {
                    Text(coreAI.lastRationale)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .accessibilityIdentifier("sidebar.coreAIRationale")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .glassEffect(.regular, in: .rect(cornerRadius: 12))
            .padding(8)
            .accessibilityIdentifier("sidebar.status")
        }
    }

    private var detailColumn: some View {
        VStack(spacing: 0) {
            tabBar
            addressBar
            if !coreAI.suggestions.isEmpty {
                suggestionStrip
            }
            webStack
            if session.showQtPanel {
                QtPanelView()
                    .frame(minHeight: 88, maxHeight: 108)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
                    .accessibilityLabel("Embedded Qt panel")
                    .accessibilityIdentifier("chrome.qtPanel")
            }
        }
    }

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(session.tabs) { tab in
                    tabChip(tab)
                }
                Button {
                    session.newTab()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.glass)
                .help("New Tab ⌘T")
                .accessibilityIdentifier("chrome.newTab")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 0))
        .accessibilityIdentifier("chrome.tabBar")
    }

    private func tabChip(_ tab: BrowserTab) -> some View {
        let selected = tab.id == session.selectedTabID
        return HStack(spacing: 6) {
            Button {
                session.selectTab(tab.id)
            } label: {
                HStack(spacing: 6) {
                    if tab.isLoading {
                        ProgressView()
                            .controlSize(.mini)
                    }
                    Text(tab.title)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                session.closeTab(tab.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.semibold))
            }
            .buttonStyle(.borderless)
            .opacity(selected ? 0.9 : 0.45)
            .help("Close Tab")
            .accessibilityIdentifier("chrome.tab.close.\(tab.id.uuidString)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(minWidth: 96, maxWidth: 180)
        .glassEffect(selected ? .regular.interactive() : .clear, in: .capsule)
        .contextMenu {
            Button("Close Tab") { session.closeTab(tab.id) }
            Button("New Tab") { session.newTab() }
            Divider()
            Button("Summarize with CoreAI") {
                Task { await session.summarizeActiveTab() }
            }
            .disabled(!coreAI.isAvailable)
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("chrome.tab.\(tab.id.uuidString)")
    }

    private var addressBar: some View {
        HStack(spacing: 8) {
            GlassEffectContainer {
                HStack(spacing: 4) {
                    Button { session.goBack() } label: {
                        Image(systemName: "chevron.backward")
                    }
                    .keyboardShortcut("[", modifiers: [.command])
                    .accessibilityIdentifier("chrome.back")

                    Button { session.goForward() } label: {
                        Image(systemName: "chevron.forward")
                    }
                    .keyboardShortcut("]", modifiers: [.command])
                    .accessibilityIdentifier("chrome.forward")

                    Button { session.reload() } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .keyboardShortcut("r", modifiers: [.command])
                    .accessibilityIdentifier("chrome.reload")

                    Button { session.goHome() } label: {
                        Image(systemName: "house")
                    }
                    .accessibilityIdentifier("chrome.home")
                }
                .buttonStyle(.glass)
            }

            HStack(spacing: 8) {
                Image(systemName: coreAI.isAvailable ? "sparkles" : "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .symbolRenderingMode(.hierarchical)
                TextField("Search or enter address", text: $session.addressField)
                    .textFieldStyle(.plain)
                    .focused($addressFocused)
                    .onSubmit { Task { await submitAddress() } }
                    .onChange(of: session.addressField) { _, newValue in
                        coreAI.scheduleSuggestions(for: newValue)
                    }
                    .accessibilityIdentifier("chrome.addressField")
                if session.isResolvingQuery || coreAI.isSuggesting {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .glassEffect(.regular.interactive(), in: .capsule)

            Button("Go") {
                Task { await submitAddress() }
            }
            .buttonStyle(.glassProminent)
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("chrome.go")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .accessibilityIdentifier("chrome.addressBar")
    }

    private var suggestionStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(coreAI.suggestions, id: \.self) { suggestion in
                    Button(suggestion) {
                        session.addressField = suggestion
                        Task { await submitAddress() }
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .accessibilityIdentifier("chrome.suggestion")
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
        }
        .accessibilityIdentifier("chrome.suggestions")
    }

    private var webStack: some View {
        ZStack {
            ForEach(session.tabs) { tab in
                WebPageView(
                    tabID: tab.id,
                    urlString: Binding(
                        get: { session.tabs.first(where: { $0.id == tab.id })?.urlString ?? "about:home" },
                        set: { session.updateURL($0, for: tab.id) }
                    ),
                    webView: Binding(
                        get: { session.webViews[tab.id] },
                        set: { session.webViews[tab.id] = $0 }
                    ),
                    isActive: tab.id == session.selectedTabID,
                    onStatus: { message in
                        session.publishStatus(message, for: tab.id)
                    },
                    onTitle: { title in
                        session.setTitle(title, for: tab.id)
                    },
                    onLoading: { loading in
                        session.setLoading(loading, for: tab.id)
                    }
                )
                .id(tab.id)
                .opacity(tab.id == session.selectedTabID ? 1 : 0)
                .allowsHitTesting(tab.id == session.selectedTabID)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 10)
        .padding(.bottom, session.showQtPanel ? 4 : 10)
        .accessibilityIdentifier("chrome.webStack")
    }

    private func submitAddress() async {
        session.isResolvingQuery = true
        defer { session.isResolvingQuery = false }
        coreAI.clearSuggestions()
        let resolved = await coreAI.resolve(session.addressField)
        session.addressField = resolved
        session.navigateActive(to: resolved)
    }
}

// MARK: - Liquid glass backdrop

private struct LiquidGlassBackdrop: View {
    var body: some View {
        ZStack {
            MeshGradient(
                width: 3,
                height: 3,
                points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [0, 0.5], [0.5, 0.5], [1, 0.5],
                    [0, 1], [0.5, 1], [1, 1],
                ],
                colors: [
                    Color(red: 0.12, green: 0.16, blue: 0.22),
                    Color(red: 0.18, green: 0.28, blue: 0.36),
                    Color(red: 0.10, green: 0.14, blue: 0.20),
                    Color(red: 0.22, green: 0.24, blue: 0.30),
                    Color(red: 0.30, green: 0.38, blue: 0.44),
                    Color(red: 0.14, green: 0.20, blue: 0.28),
                    Color(red: 0.08, green: 0.10, blue: 0.14),
                    Color(red: 0.16, green: 0.22, blue: 0.30),
                    Color(red: 0.12, green: 0.18, blue: 0.24),
                ]
            )
            .ignoresSafeArea()

            LinearGradient(
                colors: [
                    .white.opacity(0.10),
                    .clear,
                    .black.opacity(0.18),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
    }
}

// MARK: - Focused values for Commands

private struct GamaBrowserSessionKey: FocusedValueKey {
    typealias Value = BrowserSession
}

private struct GamaAddressFocusKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var gamaBrowserSession: BrowserSession? {
        get { self[GamaBrowserSessionKey.self] }
        set { self[GamaBrowserSessionKey.self] = newValue }
    }

    var gamaAddressFocus: (() -> Void)? {
        get { self[GamaAddressFocusKey.self] }
        set { self[GamaAddressFocusKey.self] = newValue }
    }
}
