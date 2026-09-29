#pragma once

/// Embeddable Qt Widgets panel for SwiftUI (`NSViewRepresentable` via winId).

#include "GamaQt.hpp"

#include <QLabel>
#include <QVBoxLayout>
#include <QWidget>

#include <string>

namespace gama {

// NOLINTBEGIN(misc-definitions-in-headers)

namespace {

struct QtPanelState {
  QWidget *root = nullptr;
  QLabel *title = nullptr;
  QLabel *status = nullptr;
};

QtPanelState &panelState() {
  static QtPanelState state;
  return state;
}

} // namespace

[[nodiscard]] void *createQtPanelNSView() {
  ensureQtApplication();
  auto &state = panelState();

  if (!state.root) {
    state.root = new QWidget;
    state.root->setAttribute(Qt::WA_NativeWindow);
    state.root->setAttribute(Qt::WA_DontCreateNativeAncestors);
    state.root->setMinimumHeight(96);
    state.root->setStyleSheet(QStringLiteral(
        "QWidget {"
        "  background-color: rgba(28, 36, 46, 210);"
        "  color: #eef3f8;"
        "  border-radius: 14px;"
        "}"
        "QLabel#title { font-size: 13px; font-weight: 600; letter-spacing: 0.2px; }"
        "QLabel#status { font-size: 11px; color: #a8b3c0; }"));

    auto *layout = new QVBoxLayout(state.root);
    layout->setContentsMargins(12, 10, 12, 10);
    layout->setSpacing(4);

    state.title = new QLabel(
        QStringLiteral("Qt %1 (embedded in SwiftUI)").arg(QLatin1String(qVersion())),
        state.root);
    state.title->setObjectName(QStringLiteral("title"));

    state.status = new QLabel(QStringLiteral("Ready — WebKit renders CSS & JS above."),
                              state.root);
    state.status->setObjectName(QStringLiteral("status"));
    state.status->setWordWrap(true);

    layout->addWidget(state.title);
    layout->addWidget(state.status);
    layout->addStretch(1);
  }

  // Materialize the Cocoa NSView backing store.
  const WId wid = state.root->winId();
  state.root->show();
  return reinterpret_cast<void *>(wid);
}

void releaseQtPanel() {
  auto &state = panelState();
  // Idempotent: SwiftUI may dismantle more than once across panel toggles.
  if (!state.root)
    return;
  delete state.root;
  state.root = nullptr;
  state.title = nullptr;
  state.status = nullptr;
}

void setQtPanelStatus(std::string text) {
  auto &state = panelState();
  if (!state.status)
    return;
  // Avoid pointless Qt layout churn for identical chrome status strings.
  const QString next = QString::fromStdString(text);
  if (state.status->text() == next)
    return;
  state.status->setText(next);
}

// NOLINTEND(misc-definitions-in-headers)

} // namespace gama
