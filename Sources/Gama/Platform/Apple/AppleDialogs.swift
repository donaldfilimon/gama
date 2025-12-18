import Foundation

#if os(macOS)
import AppKit
#endif

#if os(iOS) || os(tvOS)
import UIKit
#endif

/// Apple platform dialog utilities
public class AppleDialogs {
    public enum DialogResult {
        case ok
        case cancel
        case yes
        case no
        case abort
        case retry
        case ignore
        case `default`
    }

    public enum DialogStyle {
        case informational
        case warning
        case critical
    }

    public enum DialogButtons {
        case ok
        case okCancel
        case yesNo
        case yesNoCancel
        case retryCancel
        case abortRetryIgnore
    }

    /// Show an alert dialog (macOS)
    #if os(macOS)
    @MainActor
    public static func showAlert(
        title: String,
        message: String,
        style: DialogStyle = .informational,
        buttons: DialogButtons = .ok,
        parentWindow: NSWindow? = nil
    ) async -> DialogResult {
        await withCheckedContinuation { continuation in
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message

            // Set alert style
            switch style {
            case .informational:
                alert.alertStyle = .informational
            case .warning:
                alert.alertStyle = .warning
            case .critical:
                alert.alertStyle = .critical
            }

            // Add buttons based on configuration
            switch buttons {
            case .ok:
                alert.addButton(withTitle: "OK")
            case .okCancel:
                alert.addButton(withTitle: "OK")
                alert.addButton(withTitle: "Cancel")
            case .yesNo:
                alert.addButton(withTitle: "Yes")
                alert.addButton(withTitle: "No")
            case .yesNoCancel:
                alert.addButton(withTitle: "Yes")
                alert.addButton(withTitle: "No")
                alert.addButton(withTitle: "Cancel")
            case .retryCancel:
                alert.addButton(withTitle: "Retry")
                alert.addButton(withTitle: "Cancel")
            case .abortRetryIgnore:
                alert.addButton(withTitle: "Abort")
                alert.addButton(withTitle: "Retry")
                alert.addButton(withTitle: "Ignore")
            }

            // Show the alert
            if let parentWindow = parentWindow {
                alert.beginSheetModal(for: parentWindow) { response in
                    let result = convertResponse(response, buttons: buttons)
                    continuation.resume(returning: result)
                }
            } else {
                let response = alert.runModal()
                let result = convertResponse(response, buttons: buttons)
                continuation.resume(returning: result)
            }
        }
    }

    private static func convertResponse(_ response: NSApplication.ModalResponse, buttons: DialogButtons) -> DialogResult {
        switch response {
        case .alertFirstButtonReturn:
            switch buttons {
            case .ok, .okCancel: return .ok
            case .yesNo, .yesNoCancel: return .yes
            case .retryCancel: return .retry
            case .abortRetryIgnore: return .abort
            }
        case .alertSecondButtonReturn:
            switch buttons {
            case .okCancel: return .cancel
            case .yesNo: return .no
            case .yesNoCancel: return .no
            case .retryCancel: return .cancel
            case .abortRetryIgnore: return .retry
            }
        case .alertThirdButtonReturn:
            switch buttons {
            case .yesNoCancel: return .cancel
            case .abortRetryIgnore: return .ignore
            default: return .cancel
            }
        default:
            return .cancel
        }

        return .cancel
    }
    #endif

    /// Show an alert dialog (iOS/tvOS)
    #if os(iOS) || os(tvOS)
    @MainActor
    public static func showAlert(
        title: String,
        message: String,
        style: DialogStyle = .informational,
        buttons: DialogButtons = .ok,
        presentingViewController: UIViewController? = nil
    ) async -> DialogResult {
        await withCheckedContinuation { continuation in
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)

            // Add actions based on configuration
            switch buttons {
            case .ok:
                let okAction = UIAlertAction(title: "OK", style: .default) { _ in
                    continuation.resume(returning: .ok)
                }
                alert.addAction(okAction)

            case .okCancel:
                let okAction = UIAlertAction(title: "OK", style: .default) { _ in
                    continuation.resume(returning: .ok)
                }
                let cancelAction = UIAlertAction(title: "Cancel", style: .cancel) { _ in
                    continuation.resume(returning: .cancel)
                }
                alert.addAction(okAction)
                alert.addAction(cancelAction)

            case .yesNo:
                let yesAction = UIAlertAction(title: "Yes", style: .default) { _ in
                    continuation.resume(returning: .yes)
                }
                let noAction = UIAlertAction(title: "No", style: .default) { _ in
                    continuation.resume(returning: .no)
                }
                alert.addAction(yesAction)
                alert.addAction(noAction)

            case .yesNoCancel:
                let yesAction = UIAlertAction(title: "Yes", style: .default) { _ in
                    continuation.resume(returning: .yes)
                }
                let noAction = UIAlertAction(title: "No", style: .default) { _ in
                    continuation.resume(returning: .no)
                }
                let cancelAction = UIAlertAction(title: "Cancel", style: .cancel) { _ in
                    continuation.resume(returning: .cancel)
                }
                alert.addAction(yesAction)
                alert.addAction(noAction)
                alert.addAction(cancelAction)

            case .retryCancel:
                let retryAction = UIAlertAction(title: "Retry", style: .default) { _ in
                    continuation.resume(returning: .retry)
                }
                let cancelAction = UIAlertAction(title: "Cancel", style: .cancel) { _ in
                    continuation.resume(returning: .cancel)
                }
                alert.addAction(retryAction)
                alert.addAction(cancelAction)

            case .abortRetryIgnore:
                let abortAction = UIAlertAction(title: "Abort", style: .destructive) { _ in
                    continuation.resume(returning: .abort)
                }
                let retryAction = UIAlertAction(title: "Retry", style: .default) { _ in
                    continuation.resume(returning: .retry)
                }
                let ignoreAction = UIAlertAction(title: "Ignore", style: .default) { _ in
                    continuation.resume(returning: .ignore)
                }
                alert.addAction(abortAction)
                alert.addAction(retryAction)
                alert.addAction(ignoreAction)
            }

            // Present the alert
            if let presenter = presentingViewController ?? UIApplication.shared.keyWindow?.rootViewController {
                presenter.present(alert, animated: true, completion: nil)
            } else {
                // Fallback if no presenter found
                continuation.resume(returning: .cancel)
            }
        }
    }
    #endif

    /// Show a file open dialog (macOS only)
    #if os(macOS)
    @MainActor
    public static func showOpenDialog(
        title: String = "Open",
        allowedFileTypes: [String]? = nil,
        canChooseFiles: Bool = true,
        canChooseDirectories: Bool = false,
        allowsMultipleSelection: Bool = false,
        parentWindow: NSWindow? = nil
    ) async -> [URL]? {
        await withCheckedContinuation { continuation in
            let openPanel = NSOpenPanel()
            openPanel.title = title
            openPanel.canChooseFiles = canChooseFiles
            openPanel.canChooseDirectories = canChooseDirectories
            openPanel.allowsMultipleSelection = allowsMultipleSelection
            openPanel.allowedFileTypes = allowedFileTypes

            if let parentWindow = parentWindow {
                openPanel.beginSheetModal(for: parentWindow) { response in
                    if response == .OK {
                        continuation.resume(returning: openPanel.urls)
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            } else {
                let response = openPanel.runModal()
                if response == .OK {
                    continuation.resume(returning: openPanel.urls)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
    #endif

    /// Show a file save dialog (macOS only)
    #if os(macOS)
    @MainActor
    public static func showSaveDialog(
        title: String = "Save",
        defaultFileName: String? = nil,
        allowedFileTypes: [String]? = nil,
        parentWindow: NSWindow? = nil
    ) async -> URL? {
        await withCheckedContinuation { continuation in
            let savePanel = NSSavePanel()
            savePanel.title = title
            savePanel.nameFieldStringValue = defaultFileName ?? ""
            savePanel.allowedFileTypes = allowedFileTypes

            if let parentWindow = parentWindow {
                savePanel.beginSheetModal(for: parentWindow) { response in
                    if response == .OK {
                        continuation.resume(returning: savePanel.url)
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            } else {
                let response = savePanel.runModal()
                if response == .OK {
                    continuation.resume(returning: savePanel.url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
    #endif

    /// Show a color picker dialog (macOS only)
    #if os(macOS)
    @MainActor
    public static func showColorDialog(
        initialColor: NSColor = .black,
        parentWindow: NSWindow? = nil
    ) async -> NSColor? {
        await withCheckedContinuation { continuation in
            let colorPanel = NSColorPanel.shared
            colorPanel.setTarget(nil)
            colorPanel.setAction(nil)
            colorPanel.color = initialColor

            // Set up completion handler
            var completion: (() -> Void)?
            completion = {
                let selectedColor = colorPanel.color
                continuation.resume(returning: selectedColor)
                completion = nil
            }

            colorPanel.setTarget(self)
            colorPanel.setAction(#selector(Self.colorPanelDidChange(_:)))

            if let parentWindow = parentWindow {
                // Show as sheet
                parentWindow.beginSheet(colorPanel) { response in
                    if response == .OK {
                        completion?()
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            } else {
                // Show as standalone panel
                colorPanel.makeKeyAndOrderFront(nil)
                // For simplicity, we'll just return the initial color after a delay
                // In a real implementation, you'd need to track when the panel closes
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    continuation.resume(returning: colorPanel.color)
                }
            }
        }
    }

    @objc private static func colorPanelDidChange(_ sender: Any?) {
        // Handle color panel changes if needed
    }
    #endif
}

/// Convenience functions for common dialog patterns
public extension AppleDialogs {
    /// Show a simple information dialog
    @MainActor
    static func showInfo(title: String, message: String) async {
        #if os(macOS)
        _ = await showAlert(title: title, message: message, style: .informational, buttons: .ok)
        #else
        _ = await showAlert(title: title, message: message, style: .informational, buttons: .ok)
        #endif
    }

    /// Show a warning dialog
    @MainActor
    static func showWarning(title: String, message: String) async {
        #if os(macOS)
        _ = await showAlert(title: title, message: message, style: .warning, buttons: .ok)
        #else
        _ = await showAlert(title: title, message: message, style: .warning, buttons: .ok)
        #endif
    }

    /// Show an error dialog
    @MainActor
    static func showError(title: String, message: String) async {
        #if os(macOS)
        _ = await showAlert(title: title, message: message, style: .critical, buttons: .ok)
        #else
        _ = await showAlert(title: title, message: message, style: .critical, buttons: .ok)
        #endif
    }

    /// Show a confirmation dialog
    @MainActor
    static func showConfirm(title: String, message: String) async -> Bool {
        #if os(macOS)
        let result = await showAlert(title: title, message: message, style: .warning, buttons: .yesNo)
        return result == .yes
        #else
        let result = await showAlert(title: title, message: message, style: .warning, buttons: .yesNo)
        return result == .yes
        #endif
    }
}