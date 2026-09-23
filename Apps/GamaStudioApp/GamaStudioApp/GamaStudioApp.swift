//  GamaStudioApp.swift — the iOS and visionOS app (ADR 0008)
//
//  Everything lives in the GamaStudioEditor package product; this file only
//  puts GamaStudioView in a window and passes on files the system hands the
//  app (ADR 0010). `--smoke` checks the first layout and exits 0 or 1, for
//  tools/check.sh's simulator launch stage; `--open <path>` opens a file at
//  launch through the same path a file from Files takes. `--recovery-key <k>`
//  names the window's recovery file (ADR 0012; otherwise the window's scene
//  session does, or a fresh key under `--smoke`), and `--smoke-recovery
//  write|restore` runs the two launches of the gate's recovery check.

import Foundation
import GamaStudioEditor
import SwiftUI

@main
struct GamaStudioApp: App {
    private let isSmoke = ProcessInfo.processInfo.arguments.contains("--smoke")
    private let recoveryKey = Self.argument(after: "--recovery-key")
        ?? (ProcessInfo.processInfo.arguments.contains("--smoke") ? UUID().uuidString : nil)
    private let recoverySmoke = Self.launchRecoverySmoke()
    /// The restore smoke opens `--open` itself, after checking the restored
    /// changes; handing it over as well would meet the Untitled prompt.
    @State private var incoming: IncomingDocument? =
        Self.argument(after: "--smoke-recovery") == nil ? Self.launchArgumentDocument() : nil

    var body: some Scene {
        WindowGroup {
            GamaStudioView(
                recoveryKey: recoveryKey,
                incoming: incoming,
                recoverySmoke: recoverySmoke,
                onFirstLayout: isSmoke ? Self.reportSmoke : nil
            )
                .ignoresSafeArea(.keyboard)
                .onOpenURL { url in
                    guard url.isFileURL else { return }
                    incoming = IncomingDocument(url: url)
                }
        }
    }

    /// The value after `flag` in the launch arguments, if present.
    private static func argument(after flag: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    /// `--open <path>` from the launch arguments, if present.
    private static func launchArgumentDocument() -> IncomingDocument? {
        argument(after: "--open").map { IncomingDocument(url: URL(fileURLWithPath: $0)) }
    }

    /// `--smoke-recovery write`, or `--smoke-recovery restore` with `--open`.
    private static func launchRecoverySmoke() -> GamaStudioView.RecoverySmoke? {
        switch argument(after: "--smoke-recovery") {
        case "write": return .write
        case "restore": return argument(after: "--open").map { .restore(thenOpening: URL(fileURLWithPath: $0)) }
        default: return nil
        }
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
