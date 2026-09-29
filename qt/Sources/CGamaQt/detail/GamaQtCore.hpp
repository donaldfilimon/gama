#pragma once

/// Header-only Qt Core helpers — included from CGamaQt.cpp (not the clang module).

#include "GamaQt.hpp"

#include <QApplication>
#include <QCoreApplication>
#include <QString>
#include <QtGlobal>

#include <mutex>
#include <string>

namespace gama {

// NOLINTBEGIN(misc-definitions-in-headers)

namespace {

std::mutex &qtAppMutex() {
  static std::mutex mu;
  return mu;
}

void ensureQtApplicationUnlocked() {
  if (qobject_cast<QApplication *>(QCoreApplication::instance()))
    return;

  // Cannot upgrade a bare QCoreApplication to QApplication.
  if (QCoreApplication::instance())
    return;

  static int argc = 1;
  static char arg0[] = "gama";
  static char *argv[] = {arg0, nullptr};
  new QApplication(argc, argv);
}

} // namespace

void ensureQtApplication() {
  std::lock_guard<std::mutex> lock(qtAppMutex());
  ensureQtApplicationUnlocked();
}

[[nodiscard]] std::string qtVersion() noexcept {
  return std::string(qVersion());
}

[[nodiscard]] std::string greet(std::string name) {
  // Pure QString work — no QApplication (tests may run off the main thread).
  const QString message =
      QStringLiteral("Hello from Qt %1 via Swift/C++, %2")
          .arg(QLatin1String(qVersion()), QString::fromStdString(name));
  return message.toStdString();
}

void runWithLogger(SwiftLog log, void *context) {
  if (!log)
    return;
  log(std::string("begin"), context);
  log(std::string("qt ") + qtVersion(), context);
  log(greet(std::string("Swift")), context);
  log(std::string("end"), context);
}

void processQtEvents() {
  if (auto *app = QCoreApplication::instance())
    app->processEvents();
}

// NOLINTEND(misc-definitions-in-headers)

} // namespace gama
