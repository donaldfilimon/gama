// GamaDemo.swift — Main CLI entry point for the Gama GPU demo
// Part of GamaDemo

import ArgumentParser
import GamaCore
#if canImport(Metal)
import GamaMetal
#endif

@main
struct GamaDemo: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Gama GPU Graphics API Demo",
        subcommands: [Info.self, Triangle.self, UI.self],
        defaultSubcommand: Info.self
    )
}
