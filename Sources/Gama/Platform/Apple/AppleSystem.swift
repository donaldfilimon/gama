import Foundation

#if os(macOS)
import AppKit
#endif

#if os(iOS) || os(tvOS)
import UIKit
#endif

// Only compile this file on Apple platforms
#if os(macOS) || os(iOS) || os(tvOS)

/// Apple platform system information and utilities
public class AppleSystem {
    /// Get system information
    public static var systemInfo: SystemInfo {
        let processInfo = ProcessInfo.processInfo

        #if os(macOS)
        let host = Host.current()
        let operatingSystemVersion = processInfo.operatingSystemVersion

        return SystemInfo(
            platform: "macOS",
            version: "\(operatingSystemVersion.majorVersion).\(operatingSystemVersion.minorVersion).\(operatingSystemVersion.patchVersion)",
            build: operatingSystemVersionString,
            architecture: getArchitecture(),
            processorCount: processInfo.processorCount,
            activeProcessorCount: processInfo.activeProcessorCount,
            physicalMemory: Int64(processInfo.physicalMemory),
            hostname: host.localizedName ?? "Unknown",
            username: NSUserName(),
            userHomeDirectory: processInfo.homeDirectory.path,
            temporaryDirectory: processInfo.temporaryDirectory.path,
            isSandbox: false // macOS apps can be sandboxed but this is a general check
        )
        #else
        let device = UIDevice.current
        let operatingSystemVersion = processInfo.operatingSystemVersion

        return SystemInfo(
            platform: "iOS",
            version: "\(operatingSystemVersion.majorVersion).\(operatingSystemVersion.minorVersion).\(operatingSystemVersion.patchVersion)",
            build: operatingSystemVersionString,
            architecture: getArchitecture(),
            processorCount: processInfo.processorCount,
            activeProcessorCount: processInfo.activeProcessorCount,
            physicalMemory: Int64(processInfo.physicalMemory),
            hostname: device.name,
            username: "mobile", // iOS doesn't expose username
            userHomeDirectory: NSHomeDirectory(),
            temporaryDirectory: NSTemporaryDirectory(),
            isSandbox: true // iOS apps are always sandboxed
        )
        #endif
    }

    /// Get operating system version string
    public static var operatingSystemVersionString: String {
        let processInfo = ProcessInfo.processInfo
        return processInfo.operatingSystemVersionString
    }

    /// Get system uptime
    public static var systemUptime: TimeInterval {
        let processInfo = ProcessInfo.processInfo
        return processInfo.systemUptime
    }

    /// Get process information
    public static var processInfo: ProcessInfoData {
        let processInfo = ProcessInfo.processInfo

        return ProcessInfoData(
            processIdentifier: Int32(processInfo.processIdentifier),
            processName: processInfo.processName,
            arguments: processInfo.arguments,
            environment: processInfo.environment,
            hostName: processInfo.hostName,
            userName: NSUserName(),
            fullUserName: NSFullUserName(),
            userHomeDirectory: processInfo.homeDirectory.path
        )
    }

    /// Get memory information
    public static var memoryInfo: MemoryInfo {
        #if os(macOS)
        // Use sysctl to get memory info on macOS
        var totalMemory: Int64 = 0
        var availableMemory: Int64 = 0

        var size = MemoryLayout<Int>.size
        var total: Int = 0
        if sysctlbyname("hw.memsize", &total, &size, nil, 0) == 0 {
            totalMemory = Int64(total)
        }

        // Get available memory (approximate)
        var vmStats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let hostPort = mach_host_self()

        if host_statistics64(hostPort, HOST_VM_INFO64, &vmStats, &count) == KERN_SUCCESS {
            let pageSize = vm_kernel_page_size
            availableMemory = Int64(vmStats.free_count + vmStats.inactive_count) * Int64(pageSize)
        }

        return MemoryInfo(
            totalPhysicalMemory: totalMemory,
            availablePhysicalMemory: availableMemory,
            usedPhysicalMemory: totalMemory - availableMemory
        )
        #else
        // On iOS, use simpler approach
        let processInfo = ProcessInfo.processInfo
        let totalMemory = Int64(processInfo.physicalMemory)

        // iOS doesn't provide direct available memory info
        return MemoryInfo(
            totalPhysicalMemory: totalMemory,
            availablePhysicalMemory: 0, // Not available on iOS
            usedPhysicalMemory: 0 // Not available on iOS
        )
        #endif
    }

    /// Get CPU information
    public static var cpuInfo: CPUInfo {
        let processInfo = ProcessInfo.processInfo

        return CPUInfo(
            processorCount: processInfo.processorCount,
            activeProcessorCount: processInfo.activeProcessorCount,
            architecture: getArchitecture()
        )
    }

    /// Get disk space information
    public static var diskInfo: [DiskInfo] {
        #if os(macOS)
        let fileManager = FileManager.default
        let urls = fileManager.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey], options: [])

        return urls?.compactMap { url in
            do {
                let resourceValues = try url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeNameKey])

                guard let totalCapacity = resourceValues.volumeTotalCapacity,
                      let availableCapacity = resourceValues.volumeAvailableCapacity else {
                    return nil
                }

                return DiskInfo(
                    mountPoint: url.path,
                    name: resourceValues.volumeName ?? "Unknown",
                    totalSpace: Int64(totalCapacity),
                    availableSpace: Int64(availableCapacity),
                    usedSpace: Int64(totalCapacity - availableCapacity)
                )
            } catch {
                return nil
            }
        } ?? []
        #else
        // iOS doesn't provide direct disk info access
        return []
        #endif
    }

    /// Get network information
    public static var networkInfo: NetworkInfo {
        #if os(macOS)
        // Get network interfaces
        var interfaces: [NetworkInterface] = []
        // This would require more complex implementation with SystemConfiguration framework
        // For now, return basic info

        return NetworkInfo(
            interfaces: interfaces,
            hostname: ProcessInfo.processInfo.hostName
        )
        #else
        return NetworkInfo(
            interfaces: [],
            hostname: UIDevice.current.name
        )
        #endif
    }

    /// Check if running in sandbox
    public static var isSandboxed: Bool {
        #if os(macOS)
        // Check if we can access files outside the sandbox
        let fileManager = FileManager.default
        let testPath = "/System/Library/CoreServices/SystemVersion.plist"
        return !fileManager.fileExists(atPath: testPath)
        #else
        return true // iOS apps are always sandboxed
        #endif
    }

    /// Get the current user locale
    public static var locale: Locale {
        return Locale.current
    }

    /// Get the current user language
    public static var language: String {
        return Locale.current.language.languageCode?.identifier ?? "en"
    }

    /// Get system time zone
    public static var timeZone: TimeZone {
        return TimeZone.current
    }

    /// Sleep for specified number of seconds
    public static func sleep(seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    /// Sleep for specified number of milliseconds
    public static func sleep(milliseconds: Int) {
        let seconds = TimeInterval(milliseconds) / 1000.0
        Thread.sleep(forTimeInterval: seconds)
    }

    private static func getArchitecture() -> String {
        #if arch(x86_64)
        return "x86_64"
        #elseif arch(arm64)
        return "arm64"
        #elseif arch(i386)
        return "i386"
        #elseif arch(arm)
        return "arm"
        #else
        return "unknown"
        #endif
    }
}

/// System information structures
public struct SystemInfo {
    public let platform: String
    public let version: String
    public let build: String
    public let architecture: String
    public let processorCount: Int
    public let activeProcessorCount: Int
    public let physicalMemory: Int64
    public let hostname: String
    public let username: String
    public let userHomeDirectory: String
    public let temporaryDirectory: String
    public let isSandbox: Bool
}

public struct ProcessInfoData {
    public let processIdentifier: Int32
    public let processName: String
    public let arguments: [String]
    public let environment: [String: String]
    public let hostName: String
    public let userName: String
    public let fullUserName: String
    public let userHomeDirectory: String
}

public struct MemoryInfo {
    public let totalPhysicalMemory: Int64
    public let availablePhysicalMemory: Int64
    public let usedPhysicalMemory: Int64
}

public struct CPUInfo {
    public let processorCount: Int
    public let activeProcessorCount: Int
    public let architecture: String
}

public struct DiskInfo {
    public let mountPoint: String
    public let name: String
    public let totalSpace: Int64
    public let availableSpace: Int64
    public let usedSpace: Int64
}

public struct NetworkInterface {
    public let name: String
    public let address: String
    public let netmask: String
    public let broadcast: String?
}

public struct NetworkInfo {
    public let interfaces: [NetworkInterface]
    public let hostname: String
}

// macOS specific imports for memory info
#if os(macOS)
import Darwin

private let HOST_VM_INFO64: host_flavor_t = Int32(VM_INFO64)
private let KERN_SUCCESS: kern_return_t = 0

private func vm_kernel_page_size() -> vm_size_t {
    var pageSize: vm_size_t = 0
    var size = MemoryLayout<vm_size_t>.size
    _ = sysctlbyname("vm.kernel_page_size", &pageSize, &size, nil, 0)
    return pageSize
}
#endif
#endif