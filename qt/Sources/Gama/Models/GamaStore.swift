import Foundation
import SwiftData

enum GamaStore {
    static func makeContainer() -> ModelContainer {
        let schema = Schema([
            PersistedTab.self,
            PersistedRecent.self,
            BrowserSettings.self,
        ])
        let configuration = ModelConfiguration(
            "GamaBrowserStore",
            schema: schema,
            isStoredInMemoryOnly: false
        )
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // Schema mismatch / corrupt store — fall back to in-memory so the app still launches.
            let memory = ModelConfiguration(
                "GamaBrowserStoreMemory",
                schema: schema,
                isStoredInMemoryOnly: true
            )
            do {
                return try ModelContainer(for: schema, configurations: [memory])
            } catch {
                fatalError("Gama: could not create ModelContainer: \(error)")
            }
        }
    }
}
