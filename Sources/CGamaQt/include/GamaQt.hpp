#pragma once

/// CGamaQt — public API for Swift/C++ interop (clang module).
///
/// Implementations live in `Sources/CGamaQt/detail/*.hpp` (header-only) and are
/// compiled via the SPM stub `CGamaQt.cpp`. Detail headers stay outside
/// `publicHeadersPath` so Swift's clang module scan does not need Qt includes.

#include <string>

namespace gama {

/// Qt runtime version (e.g. "6.11.1") — no GUI required.
[[nodiscard]] std::string qtVersion() noexcept;

/// Builds a greeting with Qt Core (`QString`) and returns UTF-8 text.
[[nodiscard]] std::string greet(std::string name);

/// C++ → Swift callback. Swift passes a `gama.SwiftLog`-typed thunk.
using SwiftLog = void (*)(std::string line, void *context);

void runWithLogger(SwiftLog log, void *context = nullptr);

/// Legacy blocking Qt Widgets browser (`QApplication::exec`).
void runBrowser();

/// Create / reuse `QApplication` for SwiftUI-hosted Qt widgets.
void ensureQtApplication();

/// Pump Qt's event loop while Cocoa/SwiftUI owns the run loop.
void processQtEvents();

/// Embeddable Qt panel: returns Cocoa `NSView*` as `void*` (`QWidget::winId()`).
/// Lifetime owned by CGamaQt until `releaseQtPanel()`.
[[nodiscard]] void *createQtPanelNSView();

void releaseQtPanel();

/// Update the status label inside the embedded Qt panel.
void setQtPanelStatus(std::string text);

} // namespace gama
