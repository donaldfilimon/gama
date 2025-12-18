import Foundation
import WinSDK

/// Registry key access
public class RegistryKey {
    private var hKey: HKEY?
    
    /// Registry root keys
    public enum RootKey: HKEY {
        case classesRoot = 0x80000000
        case currentUser = 0x80000001
        case localMachine = 0x80000002
        case users = 0x80000003
        case currentConfig = 0x80000005
        case performanceData = 0x80000004
    }
    
    /// Initialize with a root key and subkey path
    public init(rootKey: RootKey, subKey: String, access: REGSAM = KEY_READ) throws {
        var hKey: HKEY?
        let result = subKey.withWindowsUTF16 { subKeyPtr in
            RegOpenKeyExW(
                rootKey.rawValue,
                subKeyPtr,
                0,
                access,
                &hKey
            )
        }
        
        guard result == ERROR_SUCCESS, let openedKey = hKey else {
            throw WindowsError.fromErrorCode(DWORD(result))
        }
        
        self.hKey = openedKey
    }
    
    /// Create or open a registry key
    public static func createOrOpen(rootKey: RootKey, subKey: String, access: REGSAM = KEY_ALL_ACCESS) throws -> RegistryKey {
        var hKey: HKEY?
        var disposition: DWORD = 0
        
        let result = subKey.withWindowsUTF16 { subKeyPtr in
            RegCreateKeyExW(
                rootKey.rawValue,
                subKeyPtr,
                0,
                nil,
                REG_OPTION_NON_VOLATILE,
                access,
                nil,
                &hKey,
                &disposition
            )
        }
        
        guard result == ERROR_SUCCESS, let createdKey = hKey else {
            throw WindowsError.fromErrorCode(DWORD(result))
        }
        
        let key = RegistryKey()
        key.hKey = createdKey
        return key
    }
    
    private init() {}
    
    /// Get string value
    public func getString(_ name: String) throws -> String {
        guard let hKey = hKey else {
            throw WindowsError.invalidHandle
        }
        
        var buffer = [WCHAR](repeating: 0, count: 1024)
        var size: DWORD = DWORD(buffer.count * MemoryLayout<WCHAR>.size)
        
        let result = name.withWindowsUTF16 { namePtr in
            RegQueryValueExW(
                hKey,
                namePtr,
                nil,
                nil,
                UnsafeMutableRawPointer(buffer.withUnsafeMutableBufferPointer { $0.baseAddress }),
                &size
            )
        }
        
        guard result == ERROR_SUCCESS else {
            throw WindowsError.fromErrorCode(DWORD(result))
        }
        
        let actualLength = Int(size) / MemoryLayout<WCHAR>.size
        buffer = Array(buffer.prefix(actualLength))
        return String(windowsUTF16: buffer.withUnsafeBufferPointer { $0.baseAddress }) ?? ""
    }
    
    /// Set string value
    public func setString(_ name: String, value: String) throws {
        guard let hKey = hKey else {
            throw WindowsError.invalidHandle
        }
        
        var utf16 = value.toWindowsUTF16NullTerminated()
        let size = DWORD(utf16.count * MemoryLayout<WCHAR>.size)
        
        let result = name.withWindowsUTF16 { namePtr in
            utf16.withUnsafeMutableBufferPointer { buffer in
                RegSetValueExW(
                    hKey,
                    namePtr,
                    0,
                    REG_SZ,
                    buffer.baseAddress,
                    size
                )
            }
        }
        
        guard result == ERROR_SUCCESS else {
            throw WindowsError.fromErrorCode(DWORD(result))
        }
    }
    
    /// Close the registry key
    public func close() {
        if let hKey = hKey {
            RegCloseKey(hKey)
            self.hKey = nil
        }
    }
    
    deinit {
        close()
    }
}