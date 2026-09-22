//  TerminalEnvironment.swift — GamaTUI
//  Process-environment lookup for capability detection. The draw layer
//  stays pure; this file is the only place that reads the variables.

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#elseif canImport(Musl)
    import Musl
#elseif canImport(Android)
    import Android
#elseif os(Windows)
    import WinSDK
#endif

public import GamaDraw

extension TerminalCapabilities {
    /// Detects capabilities from the process environment.
    ///
    /// Copies `TERM`, `COLORTERM`, `NO_COLOR`, `LC_ALL`, `LC_CTYPE`, and
    /// `LANG` into a dictionary and passes it to `detect(environment:)`.
    /// A variable that is unset is omitted, so it cannot be mistaken for
    /// support. The C string returned by the environment call is copied
    /// before this function returns.
    public static func current() -> TerminalCapabilities {
        var values: [String: String] = [:]
        for key in ["TERM", "COLORTERM", "NO_COLOR", "LANG", "LC_ALL", "LC_CTYPE"] {
            if let value = terminalEnvironment(key) {
                values[key] = value
            }
        }
        return detect(environment: values)
    }
}

/// Copies one environment variable. The pointer from the C lookup is not
/// retained: `String.init(cString:)` copies the bytes.
private func terminalEnvironment(_ name: String) -> String? {
    #if os(Windows)
        return name.withCString { pointer in
            let needed = unsafe GetEnvironmentVariableA(pointer, nil, 0)
            guard needed > 1 else { return nil }
            var buffer = [CChar](repeating: 0, count: Int(needed))
            let wrote = buffer.withUnsafeMutableBufferPointer { raw in
                unsafe GetEnvironmentVariableA(pointer, raw.baseAddress, needed)
            }
            guard wrote > 0 else { return nil }
            return String(cString: buffer)
        }
    #else
        return name.withCString { pointer in
            guard let value = unsafe getenv(pointer) else { return nil }
            return unsafe String(cString: value)
        }
    #endif
}
