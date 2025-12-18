import Foundation
#if canImport(WinSDK)
import WinSDK
#endif

/// Message box wrapper
#if canImport(WinSDK)
public struct MessageBox {
    /// Show a message box
    public static func show(
        title: String,
        message: String,
        type: UINT,
        owner: Window? = nil
    ) -> MessageBoxResult {
        let result = title.withWindowsUTF16 { titlePtr in
            message.withWindowsUTF16 { messagePtr in
                MessageBoxW(
                    owner?.hwnd,
                    messagePtr,
                    titlePtr,
                    type
                )
            }
        }
        
        return MessageBoxResult(rawValue: result) ?? .ok
    }
    
    /// Show an error message box
    public static func showError(
        title: String,
        message: String,
        owner: Window? = nil
    ) -> MessageBoxResult {
        return show(title: title, message: message, type: UINT(MB_OK | MB_ICONERROR), owner: owner)
    }
    
    /// Show a warning message box
    public static func showWarning(
        title: String,
        message: String,
        owner: Window? = nil
    ) -> MessageBoxResult {
        return show(title: title, message: message, type: UINT(MB_OK | MB_ICONWARNING), owner: owner)
    }
    
    /// Show an information message box
    public static func showInfo(
        title: String,
        message: String,
        owner: Window? = nil
    ) -> MessageBoxResult {
        return show(title: title, message: message, type: UINT(MB_OK | MB_ICONINFORMATION), owner: owner)
    }
    
    /// Show a confirmation dialog (Yes/No)
    public static func confirm(
        title: String,
        message: String,
        owner: Window? = nil
    ) -> Bool {
        let result = show(title: title, message: message, type: UINT(MB_YESNO | MB_ICONQUESTION), owner: owner)
        return result == .yes
    }
}
#endif