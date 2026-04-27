import Foundation
import SwiftUI
import WebKit

struct EPUBWebView: NSViewRepresentable {
    let fileURL: URL?
    let readAccessURL: URL?
    let anchor: String?
    let theme: ReaderTheme
    let fontSize: Double
    let lineSpacing: Double

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsMagnification = true
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.applyOrLoad(in: webView)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: EPUBWebView
        private var lastLoadedPath: String?
        private var lastAnchor: String?

        init(parent: EPUBWebView) {
            self.parent = parent
        }

        func applyOrLoad(in webView: WKWebView) {
            guard let fileURL = parent.fileURL, let readAccessURL = parent.readAccessURL else {
                webView.loadHTMLString("", baseURL: nil)
                lastLoadedPath = nil
                lastAnchor = nil
                return
            }

            let currentPath = fileURL.standardizedFileURL.path
            let anchor = parent.anchor
            if lastLoadedPath != currentPath {
                lastLoadedPath = currentPath
                lastAnchor = anchor
                webView.loadFileURL(fileURL, allowingReadAccessTo: readAccessURL)
                return
            }

            if lastAnchor != anchor {
                lastAnchor = anchor
                scrollToAnchor(in: webView)
            }

            applyTheme(in: webView)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            applyTheme(in: webView)
            scrollToAnchor(in: webView)
        }

        private func scrollToAnchor(in webView: WKWebView) {
            let anchor = parent.anchor ?? ""
            let script: String
            if anchor.isEmpty {
                script = "window.scrollTo(0, 0);"
            } else {
                script = """
                (function() {
                  const anchor = \(quoted(anchor));
                  const target = document.getElementById(anchor) || document.getElementsByName(anchor)[0];
                  if (target) {
                    target.scrollIntoView({ behavior: 'auto', block: 'start' });
                  } else {
                    location.hash = anchor;
                  }
                })();
                """
            }
            webView.evaluateJavaScript(script, completionHandler: nil)
        }

        private func applyTheme(in webView: WKWebView) {
            let script = """
            (function() {
              const styleId = 'reader-mac-native-theme';
              let style = document.getElementById(styleId);
              const host = document.head || document.documentElement;
              if (!host) {
                return;
              }
              if (!style) {
                style = document.createElement('style');
                style.id = styleId;
                host.appendChild(style);
              }

              style.textContent = `
                :root {
                  color-scheme: \(parent.theme == .night ? "dark" : "light");
                }
                html, body {
                  background: \(parent.theme.cssSurface) !important;
                  color: \(parent.theme.cssText) !important;
                  font-size: \(String(format: "%.1f", parent.fontSize))px !important;
                  line-height: \(String(format: "%.2f", parent.lineSpacing)) !important;
                  font-family: -apple-system, BlinkMacSystemFont, "PingFang SC", "Helvetica Neue", sans-serif !important;
                  margin: 0 auto !important;
                  padding: 28px 34px 54px !important;
                  max-width: 920px !important;
                }
                p, div, span, li, section, article {
                  color: \(parent.theme.cssText) !important;
                  line-height: \(String(format: "%.2f", parent.lineSpacing)) !important;
                }
                img, svg, video {
                  max-width: 100% !important;
                  height: auto !important;
                }
                a {
                  color: \(parent.theme.cssAccent) !important;
                }
              `;
            })();
            """

            webView.evaluateJavaScript(script, completionHandler: nil)
        }

        private func quoted(_ text: String) -> String {
            let escaped = text
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
            return "\"\(escaped)\""
        }
    }
}
