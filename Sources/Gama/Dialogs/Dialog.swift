import Foundation

/// Protocol for dialog implementations
public protocol DialogProtocol {
    /// Show modal dialog
    func showModal(owner: Window?) -> Int32
}

/// Cross-platform dialog box wrapper
public class Dialog: DialogProtocol {
    private let platformDialog: any DialogProtocol

    public init() {
        #if canImport(WinSDK)
        self.platformDialog = WindowsDialog()
        #else
        self.platformDialog = StubDialog()
        #endif
    }

    /// Show modal dialog (placeholder - full implementation requires dialog resource)
    public func showModal(owner: Window?) -> Int32 {
        return platformDialog.showModal(owner: owner)
    }
}

/// Stub dialog implementation for platforms without native dialog support
private class StubDialog: DialogProtocol {
    public init() {}

    /// Show modal dialog (stub implementation)
    public func showModal(owner: Window?) -> Int32 {
        print("Dialog.showModal() - stub implementation")
        return -1
    }
}