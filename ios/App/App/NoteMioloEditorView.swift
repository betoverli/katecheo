import UIKit
import WebKit

/// Callbacks from the isolated miolo WKWebView.
@MainActor
protocol NoteMioloEditorViewDelegate: AnyObject {
    func noteMioloEditorDidBecomeReady(_ editor: NoteMioloEditorView)
    func noteMioloEditor(_ editor: NoteMioloEditorView, didChangeNote raw: Any)
    func noteMioloEditor(_ editor: NoteMioloEditorView, didFail message: String)
    func noteMioloEditorDidRequestSpeaker(_ editor: NoteMioloEditorView)
}

/// **Única** superfície WKWebView do app (Fase 5 → Fase 7).
///
/// Carrega só `/native-editor` (miolo da nota). Autenticação via Bearer do Keychain
/// injectado em `localStorage`/`sessionStorage` — **não** usa cookies do host web
/// antigo nem a bridge Cap. Qualquer outra tela deve ser nativa pura.
///
/// Removido na Fase 7 (editor nativo). Ver `docs/ios-phase5-webview.md`.
@MainActor
final class NoteMioloEditorView: UIView, WKScriptMessageHandler, WKNavigationDelegate {
    weak var delegate: NoteMioloEditorViewDelegate?

    private var webView: WKWebView!
    private(set) var isReady = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setup() {
        precondition(Thread.isMainThread, "NoteMioloEditorView must be created on the main thread")
        backgroundColor = .systemBackground

        let userContent = WKUserContentController()
        userContent.add(self, name: "v2n")
        injectBearer(into: userContent)

        let config = WKWebViewConfiguration()
        config.userContentController = userContent
        // Editor bundle is remote HTTPS; no Capacitor local scheme.
        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    /// Load the dedicated native-editor page (not the full SPA).
    func loadEditor() {
        precondition(Thread.isMainThread)
        let url = NativeAPIClient.baseURL.appendingPathComponent("native-editor")
        webView.load(URLRequest(url: url))
    }

    func pushNote(_ note: NativeAPIClient.NoteDocument, speakers: [NativeAPIClient.SpeakerDTO], readOnly: Bool = false) {
        precondition(Thread.isMainThread)
        guard isReady else { return }
        guard let data = try? JSONEncoder().encode(note),
              let noteJSON = String(data: data, encoding: .utf8)
        else { return }
        let speakersJSON: String
        if let sData = try? JSONEncoder().encode(speakers),
           let s = String(data: sData, encoding: .utf8)
        {
            speakersJSON = s
        } else {
            speakersJSON = "[]"
        }
        let readOnlyLit = readOnly ? "true" : "false"
        let js = """
        (function(){
          var msg = { type: 'loadNote', note: \(noteJSON), speakers: \(speakersJSON), readOnly: \(readOnlyLit) };
          if (window.__V2N_EDITOR_LOAD__) { window.__V2N_EDITOR_LOAD__(msg); }
          else { window.postMessage(msg, '*'); }
        })();
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    private func injectBearer(into userContent: WKUserContentController) {
        guard let token = KeychainStore.bearerToken(), !token.isEmpty else { return }
        let escaped = token
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        let js = """
        try {
          window.localStorage.setItem('grok-auth.bearer-token', '\(escaped)');
          window.sessionStorage.setItem('grok-auth.bearer-token', '\(escaped)');
          window.__V2N_EDITOR__ = window.__V2N_EDITOR__ || {};
          window.__V2N_EDITOR__.bearer = '\(escaped)';
          window.__V2N_EDITOR__.bridge = true;
        } catch (e) {}
        """
        userContent.addUserScript(WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: true))
    }

    nonisolated func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "v2n" else { return }
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        Task { @MainActor in
            switch type {
            case "ready":
                self.isReady = true
                self.delegate?.noteMioloEditorDidBecomeReady(self)
            case "noteChanged":
                if let noteObj = body["note"] {
                    self.delegate?.noteMioloEditor(self, didChangeNote: noteObj)
                }
            case "error":
                self.delegate?.noteMioloEditor(self, didFail: body["message"] as? String ?? "erro")
            case "requestSpeaker":
                self.delegate?.noteMioloEditorDidRequestSpeaker(self)
            default:
                break
            }
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor in
            self.delegate?.noteMioloEditor(self, didFail: message)
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor in
            self.delegate?.noteMioloEditor(self, didFail: message)
        }
    }

    deinit {
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "v2n")
    }
}
