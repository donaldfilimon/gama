import AppKit
import Foundation
import SwiftUI
import WebKit

/// WebKit page view — full CSS and JavaScript (unlike `QTextBrowser`).
struct WebPageView: NSViewRepresentable {
    var tabID: UUID
    @Binding var urlString: String
    @Binding var webView: WKWebView?
    var isActive: Bool
    var onStatus: @MainActor (String) -> Void
    var onTitle: @MainActor (String) -> Void
    var onLoading: @MainActor (Bool) -> Void

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var parent: WebPageView

        init(_ parent: WebPageView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.onLoading(true)
            parent.onStatus("Loading…")
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.onLoading(false)
            let url = webView.url?.absoluteString ?? parent.urlString
            parent.onStatus("Loaded \(url)")
            parent.urlString = url
            webView.evaluateJavaScript("document.title") { [weak self] result, _ in
                guard let title = result as? String, !title.isEmpty else { return }
                Task { @MainActor in
                    self?.parent.onTitle(title)
                }
            }
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            parent.onLoading(false)
            parent.onStatus("Failed: \(error.localizedDescription)")
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            parent.onLoading(false)
            parent.onStatus("Failed: \(error.localizedDescription)")
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        view.allowsBackForwardNavigationGestures = true
        view.underPageBackgroundColor = .clear
        Task { @MainActor in
            self.webView = view
        }
        Self.load(urlString, into: view, onStatus: onStatus)
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.parent = self
        view.isHidden = !isActive
    }

    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        view.navigationDelegate = nil
        view.uiDelegate = nil
        _ = coordinator
    }

    static let homeHTML = """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="utf-8" />
      <meta name="viewport" content="width=device-width, initial-scale=1" />
      <title>Gama</title>
      <style>
        :root { color-scheme: dark; }
        * { box-sizing: border-box; }
        body {
          margin: 0; min-height: 100vh; display: grid; place-items: center;
          font-family: "SF Pro Rounded", ui-rounded, system-ui, sans-serif;
          background:
            radial-gradient(1200px 600px at 10% -10%, rgba(180,210,230,0.28), transparent 55%),
            radial-gradient(900px 500px at 90% 0%, rgba(140,170,200,0.22), transparent 50%),
            linear-gradient(165deg, #0c1016 0%, #151c26 45%, #0a0d12 100%);
          color: #eef3f8;
        }
        main {
          width: min(38rem, 92vw); padding: 2.1rem 2rem 1.8rem;
          border-radius: 1.6rem;
          background: linear-gradient(145deg, rgba(255,255,255,0.16), rgba(255,255,255,0.04));
          border: 1px solid rgba(255,255,255,0.22);
          box-shadow:
            0 1px 0 rgba(255,255,255,0.35) inset,
            0 24px 60px rgba(0,0,0,0.35);
          backdrop-filter: blur(28px) saturate(160%);
          -webkit-backdrop-filter: blur(28px) saturate(160%);
        }
        .brand {
          font-size: 0.72rem; letter-spacing: 0.18em; text-transform: uppercase;
          opacity: 0.65; margin-bottom: 0.55rem;
        }
        h1 {
          margin: 0 0 0.55rem; font-size: 2rem; font-weight: 650;
          letter-spacing: -0.035em;
        }
        p { margin: 0 0 1.25rem; line-height: 1.55; opacity: 0.88; }
        button {
          appearance: none; border: 0; border-radius: 999px;
          padding: 0.75rem 1.25rem; font: inherit; font-weight: 600; cursor: pointer;
          color: #0b1218;
          background: linear-gradient(135deg, #d7e6f2, #9eb6c9);
          box-shadow: 0 8px 24px rgba(0,0,0,0.25);
        }
        button:active { transform: scale(0.98); }
        #out { margin-top: 1rem; font-variant-numeric: tabular-nums; opacity: 0.8; font-size: 0.95rem; }
        kbd {
          font: 0.78rem ui-monospace, monospace; padding: 0.12rem 0.4rem;
          border-radius: 0.4rem; background: rgba(255,255,255,0.1);
          border: 1px solid rgba(255,255,255,0.18);
        }
      </style>
    </head>
    <body>
      <main>
        <div class="brand">Liquid Glass</div>
        <h1>Gama</h1>
        <p>
          Native sidebar · tabs · CoreAI address bar · WebKit CSS/JS · Qt panel.
          Try <kbd>⌘L</kbd> then “swift concurrency docs”.
        </p>
        <button id="go" type="button">Refract</button>
        <div id="out">Waiting for JS…</div>
      </main>
      <script>
        const out = document.getElementById("out");
        document.getElementById("go").addEventListener("click", () => {
          const t = new Date().toLocaleTimeString();
          out.textContent = "Liquid glass pulse · " + t;
          document.querySelector("main").animate(
            [
              { transform: "scale(1)", filter: "brightness(1)" },
              { transform: "scale(1.02)", filter: "brightness(1.08)" },
              { transform: "scale(1)", filter: "brightness(1)" }
            ],
            { duration: 420, easing: "cubic-bezier(.2,.8,.2,1)" }
          );
        });
      </script>
    </body>
    </html>
    """

    static func load(
        _ raw: String,
        into webView: WKWebView,
        onStatus: @escaping @MainActor (String) -> Void
    ) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "about:home" || trimmed == "gama:home" {
            webView.loadHTMLString(homeHTML, baseURL: URL(string: "about:home"))
            return
        }
        let text = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: text), url.scheme != nil else {
            Task { @MainActor in
                onStatus("Invalid URL")
            }
            return
        }
        webView.load(URLRequest(url: url))
    }
}
