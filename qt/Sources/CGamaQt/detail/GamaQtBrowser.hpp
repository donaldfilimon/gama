#pragma once

/// Header-only Qt Widgets + JavaScriptCore mini-browser — included from
/// CGamaQt.cpp.

#include "GamaQt.hpp"

#include <JavaScriptCore/JavaScriptCore.h>

#include <QApplication>
#include <QHBoxLayout>
#include <QLabel>
#include <QLineEdit>
#include <QMainWindow>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QPair>
#include <QPlainTextEdit>
#include <QPushButton>
#include <QSplitter>
#include <QStatusBar>
#include <QTextBrowser>
#include <QUrl>
#include <QVBoxLayout>
#include <QWidget>

#include <array>
#include <regex>
#include <string>
#include <vector>

namespace gama::detail {

struct BrowserState {
  QMainWindow *window = nullptr;
  QLineEdit *urlEdit = nullptr;
  QTextBrowser *pageView = nullptr;
  QPlainTextEdit *jsInput = nullptr;
  QPlainTextEdit *jsOutput = nullptr;
  QLabel *status = nullptr;
  QNetworkAccessManager *network = nullptr;
  JSGlobalContextRef js = nullptr;
  std::vector<QPair<QUrl, QString>> history;
  int historyIndex = -1;
  bool navigatingHistory = false;

  void appendConsole(const QString &line) {
    if (jsOutput)
      jsOutput->appendPlainText(line);
  }

  void resetJS();
  void installConsole();
};

/// Process-wide browser pointer (C++17 inline variable; one definition across
/// TUs).
inline BrowserState *g_browser = nullptr;

[[nodiscard]] inline std::string jsStringToStd(JSStringRef value) {
  const size_t size = JSStringGetMaximumUTF8CStringSize(value);
  std::string out(size, '\0');
  const size_t written = JSStringGetUTF8CString(value, out.data(), size);
  if (written > 0)
    out.resize(written - 1);
  else
    out.clear();
  return out;
}

[[nodiscard]] inline QString jsValueToQString(JSContextRef ctx,
                                              JSValueRef value) {
  if (JSValueIsUndefined(ctx, value))
    return QStringLiteral("undefined");
  if (JSValueIsNull(ctx, value))
    return QStringLiteral("null");

  JSValueRef exception = nullptr;
  JSStringRef asString = JSValueToStringCopy(ctx, value, &exception);
  if (exception || !asString)
    return QStringLiteral("[exception converting value]");
  const QString result = QString::fromStdString(jsStringToStd(asString));
  JSStringRelease(asString);
  return result;
}

inline JSValueRef consoleLog(JSContextRef ctx, JSObjectRef, JSObjectRef,
                             size_t argumentCount, const JSValueRef arguments[],
                             JSValueRef *) {
  QStringList parts;
  for (size_t i = 0; i < argumentCount; ++i)
    parts << jsValueToQString(ctx, arguments[i]);
  if (g_browser)
    g_browser->appendConsole(QStringLiteral("» ") +
                             parts.join(QLatin1Char(' ')));
  return JSValueMakeUndefined(ctx);
}

inline void BrowserState::installConsole() {
  JSObjectRef global = JSContextGetGlobalObject(js);
  JSObjectRef console = JSObjectMake(js, nullptr, nullptr);
  JSStringRef logName = JSStringCreateWithUTF8CString("log");
  JSObjectRef logFn = JSObjectMakeFunctionWithCallback(js, logName, consoleLog);
  JSObjectSetProperty(js, console, logName, logFn, kJSPropertyAttributeNone,
                      nullptr);
  JSStringRelease(logName);

  JSStringRef consoleName = JSStringCreateWithUTF8CString("console");
  JSObjectSetProperty(js, global, consoleName, console,
                      kJSPropertyAttributeNone, nullptr);
  JSStringRelease(consoleName);
}

inline void BrowserState::resetJS() {
  if (js) {
    JSGlobalContextRelease(js);
    js = nullptr;
  }
  js = JSGlobalContextCreate(nullptr);
  installConsole();
}

[[nodiscard]] inline QString evaluateJS(BrowserState &state,
                                        const QString &source) {
  if (!state.js)
    state.resetJS();

  JSStringRef script =
      JSStringCreateWithUTF8CString(source.toUtf8().constData());
  JSValueRef exception = nullptr;
  JSValueRef result =
      JSEvaluateScript(state.js, script, nullptr, nullptr, 1, &exception);
  JSStringRelease(script);

  if (exception)
    return QStringLiteral("Error: ") + jsValueToQString(state.js, exception);
  return jsValueToQString(state.js, result);
}

inline void runInlineScripts(BrowserState &state, const QString &html) {
  static const std::regex scriptRe(R"re(<script\b[^>]*>([\s\S]*?)</script>)re",
                                   std::regex::icase);
  const std::string utf8 = html.toStdString();
  auto begin = std::sregex_iterator(utf8.begin(), utf8.end(), scriptRe);
  auto end = std::sregex_iterator();
  int index = 0;
  for (auto it = begin; it != end; ++it) {
    const std::string body = (*it)[1].str();
    if (body.empty())
      continue;
    ++index;
    const QString result = evaluateJS(state, QString::fromStdString(body));
    state.appendConsole(
        QStringLiteral("[script #%1] → %2").arg(index).arg(result));
  }
}

/// Prefer `QString::fromUtf8(R"…")` over `QStringLiteral(R"…")` — the latter
/// expands to `u""` and cannot concatenate with a raw string literal.
[[nodiscard]] inline QString homeHTML() {
  return QString::fromUtf8(R"html(
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><title>Gama</title></head>
<body style="font-family: -apple-system, sans-serif; margin: 2rem; line-height: 1.5;">
  <h1>Gama Browser</h1>
  <p>Qt Widgets window + <b>JavaScriptCore</b> for scripts.</p>
  <ul>
    <li>Enter a URL (https://…) and press Go</li>
    <li>Inline <code>&lt;script&gt;</code> tags run in JavaScriptCore</li>
    <li>Use the console below for interactive JS</li>
  </ul>
  <script>
    console.log("home script: JavaScriptCore is ready");
    "welcome";
  </script>
</body>
</html>
)html");
}

inline void showDocument(BrowserState &state, const QUrl &url,
                         const QString &html, bool addHistory) {
  state.resetJS();
  if (state.jsOutput)
    state.jsOutput->clear();
  state.pageView->document()->setBaseUrl(url);
  state.pageView->setHtml(html);
  state.urlEdit->setText(url.toString());
  if (state.status)
    state.status->setText(url.toString());

  if (addHistory && !state.navigatingHistory) {
    if (state.historyIndex >= 0 &&
        state.historyIndex + 1 < static_cast<int>(state.history.size()))
      state.history.resize(static_cast<size_t>(state.historyIndex + 1));
    state.history.push_back(qMakePair(url, html));
    state.historyIndex = static_cast<int>(state.history.size()) - 1;
  }

  runInlineScripts(state, html);
}

inline void loadURL(BrowserState &state, const QString &raw) {
  QString text = raw.trimmed();
  if (text.isEmpty() || text == QLatin1String("about:home") ||
      text == QLatin1String("gama:home")) {
    showDocument(state, QUrl(QStringLiteral("about:home")), homeHTML(), true);
    return;
  }
  if (!text.contains(QLatin1String("://")))
    text.prepend(QStringLiteral("https://"));

  const QUrl url(text);
  if (!url.isValid()) {
    state.appendConsole(QStringLiteral("Invalid URL: ") + text);
    return;
  }

  if (state.status)
    state.status->setText(QStringLiteral("Loading %1…").arg(url.toString()));

  QNetworkRequest request(url);
  request.setHeader(QNetworkRequest::UserAgentHeader,
                    QStringLiteral("GamaBrowser/1.0 (Qt; JavaScriptCore)"));
  QNetworkReply *reply = state.network->get(request);
  QObject::connect(reply, &QNetworkReply::finished, reply, [reply, url]() {
    reply->deleteLater();
    if (!g_browser)
      return;
    if (reply->error() != QNetworkReply::NoError) {
      g_browser->appendConsole(QStringLiteral("Load failed: ") +
                               reply->errorString());
      if (g_browser->status)
        g_browser->status->setText(reply->errorString());
      return;
    }
    const QByteArray bytes = reply->readAll();
    const QString html = QString::fromUtf8(bytes);
    showDocument(*g_browser, url, html, true);
  });
}

} // namespace gama::detail

namespace gama {

// Non-inline: emitted by CGamaQt.cpp so Swift/C++ interop can link.
// NOLINTNEXTLINE(misc-definitions-in-headers)
void runBrowser() {
  using detail::BrowserState;
  using detail::evaluateJS;
  using detail::g_browser;
  using detail::loadURL;
  using detail::showDocument;

  ensureQtApplication();
  auto *app = qobject_cast<QApplication *>(QCoreApplication::instance());
  if (!app)
    return;

  app->setApplicationName(QStringLiteral("Gama"));
  app->setOrganizationName(QStringLiteral("Gama"));

  BrowserState state;
  g_browser = &state;
  state.resetJS();
  state.network = new QNetworkAccessManager(app);

  state.window = new QMainWindow;
  state.window->setWindowTitle(QStringLiteral("Gama Browser"));
  state.window->resize(1100, 760);

  auto *central = new QWidget(state.window);
  auto *root = new QVBoxLayout(central);

  auto *toolbar = new QWidget(central);
  auto *toolbarLayout = new QHBoxLayout(toolbar);
  toolbarLayout->setContentsMargins(0, 0, 0, 0);

  auto *backButton = new QPushButton(QStringLiteral("←"), toolbar);
  auto *forwardButton = new QPushButton(QStringLiteral("→"), toolbar);
  auto *reloadButton = new QPushButton(QStringLiteral("↻"), toolbar);
  auto *homeButton = new QPushButton(QStringLiteral("Home"), toolbar);
  state.urlEdit = new QLineEdit(toolbar);
  state.urlEdit->setPlaceholderText(
      QStringLiteral("https://example.com or about:home"));
  auto *goButton = new QPushButton(QStringLiteral("Go"), toolbar);

  toolbarLayout->addWidget(backButton);
  toolbarLayout->addWidget(forwardButton);
  toolbarLayout->addWidget(reloadButton);
  toolbarLayout->addWidget(homeButton);
  toolbarLayout->addWidget(state.urlEdit, 1);
  toolbarLayout->addWidget(goButton);

  auto *splitter = new QSplitter(Qt::Vertical, central);
  state.pageView = new QTextBrowser(splitter);
  state.pageView->setOpenExternalLinks(false);
  state.pageView->setOpenLinks(false);

  auto *consolePane = new QWidget(splitter);
  auto *consoleLayout = new QVBoxLayout(consolePane);
  consoleLayout->setContentsMargins(0, 0, 0, 0);
  consoleLayout->addWidget(
      new QLabel(QStringLiteral("JavaScriptCore console"), consolePane));
  state.jsOutput = new QPlainTextEdit(consolePane);
  state.jsOutput->setReadOnly(true);
  state.jsOutput->setMaximumBlockCount(2000);
  state.jsInput = new QPlainTextEdit(consolePane);
  state.jsInput->setPlaceholderText(
      QStringLiteral("JavaScript… (⌘/Ctrl+Enter to run)"));
  state.jsInput->setFixedHeight(90);
  auto *runJSButton = new QPushButton(QStringLiteral("Run JS"), consolePane);
  consoleLayout->addWidget(state.jsOutput, 1);
  consoleLayout->addWidget(state.jsInput);
  consoleLayout->addWidget(runJSButton);

  splitter->addWidget(state.pageView);
  splitter->addWidget(consolePane);
  splitter->setStretchFactor(0, 3);
  splitter->setStretchFactor(1, 1);

  root->addWidget(toolbar);
  root->addWidget(splitter, 1);
  state.window->setCentralWidget(central);
  state.status = new QLabel(state.window);
  state.window->statusBar()->addWidget(state.status, 1);

  const auto navigate = [&state]() { loadURL(state, state.urlEdit->text()); };

  QObject::connect(goButton, &QPushButton::clicked, state.window, navigate);
  QObject::connect(state.urlEdit, &QLineEdit::returnPressed, state.window,
                   navigate);
  QObject::connect(homeButton, &QPushButton::clicked, state.window, [&state]() {
    loadURL(state, QStringLiteral("about:home"));
  });
  QObject::connect(reloadButton, &QPushButton::clicked, state.window, navigate);
  QObject::connect(backButton, &QPushButton::clicked, state.window, [&state]() {
    if (state.historyIndex <= 0)
      return;
    state.navigatingHistory = true;
    --state.historyIndex;
    const auto &entry = state.history[static_cast<size_t>(state.historyIndex)];
    showDocument(state, entry.first, entry.second, false);
    state.navigatingHistory = false;
  });
  QObject::connect(
      forwardButton, &QPushButton::clicked, state.window, [&state]() {
        if (state.historyIndex + 1 >= static_cast<int>(state.history.size()))
          return;
        state.navigatingHistory = true;
        ++state.historyIndex;
        const auto &entry =
            state.history[static_cast<size_t>(state.historyIndex)];
        showDocument(state, entry.first, entry.second, false);
        state.navigatingHistory = false;
      });

  QObject::connect(
      state.pageView, &QTextBrowser::anchorClicked, state.window,
      [&state](const QUrl &url) { loadURL(state, url.toString()); });

  const auto runConsole = [&state]() {
    const QString source = state.jsInput->toPlainText().trimmed();
    if (source.isEmpty())
      return;
    state.appendConsole(QStringLiteral("› ") + source);
    state.appendConsole(QStringLiteral("→ ") + evaluateJS(state, source));
  };
  QObject::connect(runJSButton, &QPushButton::clicked, state.window,
                   runConsole);

  loadURL(state, QStringLiteral("about:home"));
  state.window->show();
  app->exec();

  if (state.js) {
    JSGlobalContextRelease(state.js);
    state.js = nullptr;
  }
  g_browser = nullptr;
}

} // namespace gama
