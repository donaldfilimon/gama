//  GamaStudioApp.swift — the iOS and visionOS app (ADR 0008)
//
//  Everything lives in the GamaStudioEditor package product; this file only
//  puts GamaStudioView in a window. `--smoke` checks the first layout and
//  exits 0 or 1, for tools/check.sh's simulator launch stage.

import Foundation
import GamaStudioEditor
import SwiftUI

@main
struct GamaStudioApp: App {
    private let isSmoke = ProcessInfo.processInfo.arguments.contains("--smoke")

    var body: some Scene {
        WindowGroup {
            GamaStudioView(onFirstLayout: isSmoke ? Self.reportSmoke : nil)
                .ignoresSafeArea(.keyboard)
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
