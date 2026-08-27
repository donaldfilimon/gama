#if canImport(Foundation)
    import Foundation
    import GamaCore
    import GamaPlatformServices
    import GamaPlugin
    import Testing

    @Suite("Platform services: scoped filesystem, clock, log")
    struct PlatformServicesTests {
        private func makeScratchDirectory() throws -> String {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("gama-plugin-fs-\(UUID().uuidString)")
            try FileManager.default.createDirectory(
                at: url, withIntermediateDirectories: true)
            return url.path
        }

        @Test("dot-dot traversal out of the granted prefix is refused")
        func dotDotEscape() {
            let scope = FilesystemScope.read(pathPrefix: "/private/tmp/gama-scope")
            let hostile = "/private/tmp/gama-scope/../secrets"
            #expect(!scope.permitsRead(hostile))
            #expect(throws: PluginError.accessDenied(path: hostile)) {
                _ = try FilesystemProvider.standard.read(hostile, scope)
            }
        }

        @Test("absolute paths outside the prefix are refused")
        func absoluteEscape() {
            let scope = FilesystemScope.read(pathPrefix: "/private/tmp/gama-scope")
            #expect(throws: PluginError.accessDenied(path: "/etc/passwd")) {
                _ = try FilesystemProvider.standard.read("/etc/passwd", scope)
            }
        }

        @Test("an empty prefix denies everything: fail closed, never grant-all")
        func emptyPrefixDeniesAll() {
            let scope = FilesystemScope.read(pathPrefix: "")
            #expect(!scope.permitsRead("/anything"))
            #expect(throws: PluginError.accessDenied(path: "/anything")) {
                _ = try FilesystemProvider.standard.read("/anything", scope)
            }
        }

        @Test("prefix containment stops at component boundaries: /a never covers /ab")
        func componentBoundary() {
            let scope = FilesystemScope.readWrite(pathPrefix: "/a")
            #expect(scope.permitsRead("/a"))
            #expect(scope.permitsRead("/a/b"))
            #expect(!scope.permitsRead("/ab"))
            #expect(!scope.permitsRead("/ab/c"))
            #expect(!scope.permitsRead("a/b"))
        }

        @Test("read-only scopes refuse writes; readWrite scopes allow them")
        func readOnlyVersusReadWrite() {
            let readOnly = FilesystemScope.read(pathPrefix: "/a")
            #expect(!readOnly.permitsWrite("/a/file"))
            #expect(throws: PluginError.accessDenied(path: "/a/file")) {
                try FilesystemProvider.standard.write([1], "/a/file", readOnly)
            }
            #expect(FilesystemScope.readWrite(pathPrefix: "/a").permitsWrite("/a/file"))
        }

        @Test("a granted write/read roundtrips real bytes on disk")
        func scopedRoundtrip() throws {
            let directory = try makeScratchDirectory()
            defer { try? FileManager.default.removeItem(atPath: directory) }
            let scope = FilesystemScope.readWrite(pathPrefix: directory)
            let path = directory + "/note.bin"
            let payload: [UInt8] = [0, 1, 2, 250, 255]

            try FilesystemProvider.standard.write(payload, path, scope)
            let echoed = try FilesystemProvider.standard.read(path, scope)
            #expect(echoed == payload)
        }

        @Test("a missing file inside the scope reports ioFailure, not accessDenied")
        func missingFileIsIOFailure() throws {
            let directory = try makeScratchDirectory()
            defer { try? FileManager.default.removeItem(atPath: directory) }
            let scope = FilesystemScope.read(pathPrefix: directory)
            let path = directory + "/absent.bin"
            #expect(throws: PluginError.ioFailure(path: path)) {
                _ = try FilesystemProvider.standard.read(path, scope)
            }
        }

        @Test("standard services expose log, a monotonic clock, and a filesystem")
        func standardServicesPresent() {
            let services = HostServices.standard
            #expect(services.log != nil)
            #expect(services.filesystem != nil)
            let clock = services.clock
            #expect(clock != nil)
            if let clock {
                let first = clock()
                let second = clock()
                #expect(second >= first)
            }
        }

        @Test("granted handles reach the real provider through the runtime")
        func handlesThroughRuntime() throws {
            let directory = try makeScratchDirectory()
            defer { try? FileManager.default.removeItem(atPath: directory) }
            let scope = FilesystemScope.readWrite(pathPrefix: directory)
            let capability = Capability.filesystem(scope)

            final class ContextBox: @unchecked Sendable {
                var context: PluginContext?
            }
            struct FSPlugin: GamaPluginProtocol {
                let capability: Capability
                let box: ContextBox
                var manifest: PluginManifest {
                    PluginManifest(
                        id: "test.fs",
                        version: PluginVersion(major: 1, minor: 0, patch: 0),
                        requires: [capability]
                    )
                }
                mutating func activate(in context: PluginContext) throws(PluginError) {
                    box.context = context
                }
            }

            let box = ContextBox()
            let runtime = PluginRuntime(
                grants: CapabilityGrants(table: ["test.fs": [capability]]),
                services: HostServices(filesystem: .standard),
                subscriptions: SubscriptionContext {}
            )
            try runtime.install(FSPlugin(capability: capability, box: box))
            let filesystem = try #require(box.context?.filesystem)

            let inside = directory + "/data.bin"
            try filesystem.write([9, 9, 9], path: inside)
            #expect(try filesystem.read(path: inside) == [9, 9, 9])
            #expect(throws: PluginError.accessDenied(path: "/etc/hosts")) {
                _ = try filesystem.read(path: "/etc/hosts")
            }
        }
    }
#endif
