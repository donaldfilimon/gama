//  GamaStudioApp.swift — the iOS and visionOS app (ADR 0008)
//
//  Everything lives in the GamaStudioEditor package product; this file only
//  puts GamaStudioView in a window and passes on files the system hands the
//  app (ADR 0010). `--smoke` checks the first layout and exits 0 or 1, for
//  tools/check.sh's simulator launch stage; `--open <path>` opens a file at
//  launch through the same path a file from Files takes.

import Foundation
import GamaStudioEditor
import SwiftUI

@main
struct GamaStudioApp: App {
    private let isSmoke = ProcessInfo.processInfo.arguments.contains("--smoke")
    @State private var incoming: IncomingDocument? = Self.launchArgumentDocument()

    var body: some Scene {
        WindowGroup {
            GamaStudioView(incoming: incoming, onFirstLayout: isSmoke ? Self.reportSmoke : nil)
                .ignoresSafeArea(.keyboard)
                .onOpenURL { url in
                    guard url.isFileURL else { return }
                    incoming = IncomingDocument(url: url)
                }
        }
    }

    /// `--open <path>` from the launch arguments, if present.
    private static func launchArgumentDocument() -> IncomingDocument? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "--open"), arguments.indices.contains(flag + 1) else { return nil }
        return IncomingDocument(url: URL(fileURLWithPath: arguments[flag + 1]))
    }

    @MainActor
    private static func reportSmoke(_ failures: [String]) {
        if failures.isEmpty {
            print("gama-studio-app smoke: OK")
            exit(0)
        }
        print("gama-studio-app smoke: FAILED (\(failures.joined(separator: "; ")))")
        exit(1)
    }
}
