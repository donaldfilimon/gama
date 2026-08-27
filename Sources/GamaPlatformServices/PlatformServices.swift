//  PlatformServices.swift — GamaPlatformServices
//  First-party HostServices implementations for platforms with an OS.
//  This target is platform-conditional and may import Foundation; it is
//  never imported by GamaCore, GamaPlugin, GamaDraw, or any portable
//  target (check-boundaries.sh enforces the inverse grep). On platforms
//  without an OS (wasm32, Embedded) portable code never references it,
//  so exclusion is structural rather than a runtime check.

#if canImport(Foundation)
    import Foundation
    import GamaCore
    import GamaPlugin

    extension FilesystemProvider {
        /// The real filesystem, honoring ``FilesystemScope`` path
        /// prefixes: every operation re-checks lexical containment of the
        /// absolute path in the granted scope (defense in depth on top of
        /// ``FilesystemAccess``) before touching the disk.
        ///
        /// Containment is exact prefix containment on the path as given,
        /// with no symlink resolution: a documented V1 limitation, so a
        /// symlink inside a granted prefix can point outside it. Paths
        /// containing `.` or `..` components, relative paths, and empty
        /// prefixes are refused outright.
        public static var standard: FilesystemProvider {
            FilesystemProvider(
                read: { (path, scope) throws(PluginError) -> [UInt8] in
                    guard scope.permitsRead(path) else {
                        throw PluginError.accessDenied(path: path)
                    }
                    guard let data = FileManager.default.contents(atPath: path) else {
                        throw PluginError.ioFailure(path: path)
                    }
                    return [UInt8](data)
                },
                write: { (bytes, path, scope) throws(PluginError) -> Void in
                    guard scope.permitsWrite(path) else {
                        throw PluginError.accessDenied(path: path)
                    }
                    do {
                        try Data(bytes).write(to: URL(fileURLWithPath: path))
                    } catch {
                        throw PluginError.ioFailure(path: path)
                    }
                }
            )
        }
    }

    extension HostServices {
        /// Ready-made services for OS-backed hosts: a stderr log sink, a
        /// monotonic millisecond clock, and the
        /// ``FilesystemProvider/standard`` filesystem provider.
        public static var standard: HostServices {
            HostServices(
                log: { plugin, message in
                    let line = "[\(plugin.raw)] \(message)\n"
                    FileHandle.standardError.write(Data(line.utf8))
                },
                clock: {
                    // systemUptime is monotonic while the machine is
                    // awake; the epoch (boot) is host-defined, which is
                    // all ClockAccess promises.
                    UInt64(ProcessInfo.processInfo.systemUptime * 1000)
                },
                filesystem: .standard
            )
        }
    }
#endif
