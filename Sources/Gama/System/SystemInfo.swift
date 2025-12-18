import Foundation
#if canImport(WinSDK)
import WinSDK
#endif

/// System information utilities
#if canImport(WinSDK)
public struct SystemInfo {
    /// Get Windows version information
    public static func getWindowsVersion() -> (major: DWORD, minor: DWORD, build: DWORD) {
        var versionInfo = OSVERSIONINFOW()
        versionInfo.dwOSVersionInfoSize = DWORD(MemoryLayout<OSVERSIONINFOW>.size)
        
        if GetVersionExW(&versionInfo) != 0 {
            return (versionInfo.dwMajorVersion, versionInfo.dwMinorVersion, versionInfo.dwBuildNumber)
        }
        
        return (0, 0, 0)
    }
    
    /// Get system metrics
    public static func getSystemMetric(_ index: Int32) -> Int32 {
        return GetSystemMetrics(index)
    }
    
    /// Get screen width
    public static var screenWidth: Int32 {
        return getSystemMetric(SM_CXSCREEN)
    }
    
    /// Get screen height
    public static var screenHeight: Int32 {
        return getSystemMetric(SM_CYSCREEN)
    }
    
    /// Get screen size
    public static var screenSize: Size {
        return Size(width: screenWidth, height: screenHeight)
    }
    
    /// Get computer name
    public static func getComputerName() -> String {
        var buffer = [WCHAR](repeating: 0, count: MAX_COMPUTERNAME_LENGTH + 1)
        var size: DWORD = DWORD(buffer.count)
        
        guard GetComputerNameW(&buffer, &size) != 0 else {
            return ""
        }
        
        return String(windowsUTF16: buffer.withUnsafeBufferPointer { $0.baseAddress }) ?? ""
    }
    
    /// Get user name
    public static func getUserName() -> String {
        var buffer = [WCHAR](repeating: 0, count: 256)
        var size: DWORD = DWORD(buffer.count)
        
        guard GetUserNameW(&buffer, &size) != 0 else {
            return ""
        }
        
        return String(windowsUTF16: buffer.withUnsafeBufferPointer { $0.baseAddress }) ?? ""
    }
}
#endif