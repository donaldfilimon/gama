import AppKit
import SwiftUI

/// Hosts an embeddable Qt `QWidget` inside SwiftUI via Cocoa `NSView`
/// (`QWidget::winId()` → `NSView*` on macOS).
///
/// Ownership: CGamaQt owns the `QWidget` until `GamaQt.releasePanel()`.
/// This view only retains an unowned `NSView` reference for layout.
struct QtPanelView: NSViewRepresentable {
    final class Coordinator {
        /// Unretained Cocoa view backed by Qt (`winId`); do not `release`.
        weak var hostedView: NSView?
        var didEmbed = false
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 100))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor
        container.setAccessibilityIdentifier("chrome.qtPanel")
        container.setAccessibilityLabel("Embedded Qt panel")

        embedQtView(into: container, coordinator: context.coordinator)
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Retry embed until QApplication / winId are ready (first frames can miss).
        if !context.coordinator.didEmbed {
            embedQtView(into: nsView, coordinator: context.coordinator)
        }
        if let hosted = context.coordinator.hostedView {
            hosted.frame = nsView.bounds
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.hostedView?.removeFromSuperview()
        coordinator.hostedView = nil
        coordinator.didEmbed = false
        GamaQt.releasePanel()
    }

    private func embedQtView(into container: NSView, coordinator: Coordinator) {
        guard !coordinator.didEmbed else { return }

        GamaQt.ensureApplication()
        guard let opaque = GamaQt.createPanelNSView() else {
            return
        }

        // Qt Cocoa: winId() is an NSView*.
        let qtView = Unmanaged<NSView>.fromOpaque(opaque).takeUnretainedValue()
        qtView.translatesAutoresizingMaskIntoConstraints = true
        qtView.autoresizingMask = [.width, .height]
        qtView.frame = container.bounds
        qtView.setAccessibilityIdentifier("chrome.qtPanel.hosted")
        container.subviews.forEach { $0.removeFromSuperview() }
        container.addSubview(qtView)
        coordinator.hostedView = qtView
        coordinator.didEmbed = true
    }
}
