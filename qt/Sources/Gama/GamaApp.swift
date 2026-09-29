import Foundation
import SwiftData
import SwiftUI

/// CLI-only paths that exit before the SwiftUI app runs.
enum GamaCLI {
    static func runIfRequested() -> Bool {
        var args = Array(CommandLine.arguments.dropFirst())
        if args.isEmpty { return false }

        if args.contains("--legacy-browser") {
            GamaQt.runLegacyBrowser()
            return true
        }

        if args.contains("--callback") {
            for line in GamaQt.runWithLogger() {
                print(line)
            }
            return true
        }

        if args.contains("--help") || args.contains("-h") {
            print(
                """
                OVERVIEW: Gama — SwiftUI + SwiftData browser · Qt · CoreAI

                USAGE: gama [--callback] [--legacy-browser] [<name>]

                  (default)           SwiftUI window (sidebar · tabs · WebKit · Qt)
                  --callback          C++ → Swift logger demo (stdout)
                  --legacy-browser    Blocking Qt Widgets browser
                  <name>              Print Qt greet line and exit

                Shortcuts: ⌘T new tab · ⌘W close · ⌘L address · ⌘R reload · ⌘[ ] history
                           ⌘⇧I CoreAI page insight
                """
            )
            return true
        }

        args.removeAll { $0.hasPrefix("-") }
        if let name = args.first {
            print("Qt \(GamaQt.version())")
            print(GamaQt.greet(name: name))
            return true
        }

        return false
    }
}

@main
struct GamaApp: App {
    private let modelContainer: ModelContainer
    @State private var session: BrowserSession

    init() {
        if GamaCLI.runIfRequested() {
            Foundation.exit(EXIT_SUCCESS)
        }
        GamaQt.ensureApplication()
        SmartSearchService.shared.refreshAvailability()

        let container = GamaStore.makeContainer()
        modelContainer = container
        _session = State(initialValue: BrowserSession(modelContext: container.mainContext))
    }

    var body: some Scene {
        WindowGroup("Gama") {
            ContentView(session: session)
        }
        .defaultSize(width: 1180, height: 800)
        .modelContainer(modelContainer)
        .commands {
            GamaCommands()
        }
    }
}

struct GamaCommands: Commands {
    @FocusedValue(\.gamaBrowserSession) private var session
    @FocusedValue(\.gamaAddressFocus) private var focusAddress

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Tab") {
                session?.newTab()
            }
            .keyboardShortcut("t", modifiers: [.command])

            Button("Close Tab") {
                session?.closeSelectedTab()
            }
            .keyboardShortcut("w", modifiers: [.command])
        }

        CommandMenu("View") {
            Button("Toggle Sidebar") {
                guard let session else { return }
                session.columnVisibility = session.columnVisibility == .all ? .detailOnly : .all
            }
            .keyboardShortcut("s", modifiers: [.command, .control])

            Button("Toggle Qt Panel") {
                session?.showQtPanel.toggle()
            }
            .keyboardShortcut("j", modifiers: [.command, .shift])
        }

        CommandMenu("Navigation") {
            Button("Open Location…") {
                focusAddress?()
            }
            .keyboardShortcut("l", modifiers: [.command])

            Button("Reload") {
                session?.reload()
            }
            .keyboardShortcut("r", modifiers: [.command])

            Button("Back") {
                session?.goBack()
            }
            .keyboardShortcut("[", modifiers: [.command])

            Button("Forward") {
                session?.goForward()
            }
            .keyboardShortcut("]", modifiers: [.command])

            Divider()

            Button("Show Previous Tab") {
                session?.selectRelativeTab(offset: -1)
            }
            .keyboardShortcut("[", modifiers: [.command, .shift])

            Button("Show Next Tab") {
                session?.selectRelativeTab(offset: 1)
            }
            .keyboardShortcut("]", modifiers: [.command, .shift])
        }

        CommandMenu("CoreAI") {
            Button("Summarize This Tab") {
                Task { await session?.summarizeActiveTab() }
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])
            .disabled(!(SmartSearchService.shared.isAvailable))

            Button("Refresh CoreAI Availability") {
                SmartSearchService.shared.refreshAvailability()
            }
        }
    }
}
