import AppKit
import WebKit
import ChemCraftCore

/// Browser confirmations and workflow actions for the trusted local editor only.
@MainActor
final class ChemRefineWebDelegate: NSObject, WKUIDelegate, WKScriptMessageHandlerWithReply {
    var allowedURL: URL?
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage, replyHandler: @escaping (Any?, String?) -> Void) {
        guard message.frameInfo.isMainFrame,
              let url = message.frameInfo.request.url, let allowedURL,
              url.host == "127.0.0.1", url.port == allowedURL.port,
              let payload = message.body as? [String: Any], let action = payload["action"] as? String else {
            replyHandler(nil, "Workflow requests must come from the local editor."); return
        }
        Task {
            do {
                let data: Data
                if action == "summary" {
                    // Read exactly the config open in this editor, without saving pending edits.
                    guard let browser = message.webView,
                          let path = try await browser.evaluateJavaScript("Alpine.$data(document.body).savedPath") as? String else {
                        throw ParseError.malformed("Open a workflow first.")
                    }
                    data = try await WorkflowRunner.shared.bridge(action: "summary", path: path)
                } else if action == "copy" {
                    guard let text = payload["text"] as? String else { throw ParseError.malformed("No table to copy.") }
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
                    replyHandler(["copied": true], nil); return
                } else {
                    data = try await WorkflowRunner.shared.launchFromEditor(action: action, target: payload["target"] as? String)
                }
                replyHandler(try JSONSerialization.jsonObject(with: data), nil)
            } catch { replyHandler(nil, error.localizedDescription) }
        }
    }
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = NSAlert(); alert.messageText = "ChemRefine"; alert.informativeText = message
        alert.addButton(withTitle: "Continue"); alert.addButton(withTitle: "Cancel")
        if let window = webView.window { alert.beginSheetModal(for: window) { completionHandler($0 == .alertFirstButtonReturn) } }
        else { completionHandler(false) }
    }
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = NSAlert(); alert.messageText = "ChemRefine"; alert.informativeText = message
        if let window = webView.window { alert.beginSheetModal(for: window) { _ in completionHandler() } }
        else { completionHandler() }
    }
    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        let alert = NSAlert(); alert.messageText = "ChemRefine"; alert.informativeText = prompt
        let field = NSTextField(string: defaultText ?? ""); field.frame = NSRect(x: 0, y: 0, width: 420, height: 24)
        alert.accessoryView = field; alert.addButton(withTitle: "OK"); alert.addButton(withTitle: "Cancel")
        if let window = webView.window { alert.beginSheetModal(for: window) { completionHandler($0 == .alertFirstButtonReturn ? field.stringValue : nil) } }
        else { completionHandler(nil) }
    }
}
