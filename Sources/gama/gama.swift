import ArgumentParser

@main
struct gama: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "gama",
        abstract: "gama TUI framework",
        version: "0.1.0",
        subcommands: [Demo.self]
    )
}

struct Demo: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "demo",
        abstract: "Run the gama widget showcase"
    )

    func run() throws {
        var app = DemoApp()
        try app.run()
    }
}
