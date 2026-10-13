import Foundation
import UIKit
import WebKit
import XCTest
@testable import ChatGPTWebOptimized

/// iOS WebKit fixture only. No ChatGPT account, cookies, request interception, or production UI changes.
@MainActor
final class ResultOnlyWebKitFeasibilityTests: XCTestCase {
    private struct Snapshot: Decodable {
        let mode: String
        let domNodes: Int
        let mountedIntermediate: Int
        let hiddenIntermediate: Int
        let modelIntermediate: Int
        let retainedPayloadBytes: Int
        let mountedFinal: Int
        let actionButtons: Int
        let layoutMs: Double
    }

    private final class LoadDelegate: NSObject, WKNavigationDelegate {
        let finished: XCTestExpectation
        var navigationError: Error?
        init(_ finished: XCTestExpectation) { self.finished = finished }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            finished.fulfill()
        }
        func webView(_ webView: WKWebView,
                     didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            navigationError = error
            finished.fulfill()
        }
    }

    func testResultOnlyModesAndRetainedIntermediateState() async throws {
        let full = try await sample("full")
        let css = try await sample("css_hidden")
        let offscreen = try await sample("offscreen")
        let pruned = try await sample("dom_pruned")
        let ownedFrontend = try await sample("owned_final_only")

        // CSS changes visibility, not React-owned records or DOM creation.
        XCTAssertGreaterThan(full.mountedIntermediate, 2000)
        XCTAssertEqual(css.mountedIntermediate, full.mountedIntermediate)
        XCTAssertEqual(css.domNodes, full.domNodes)
        XCTAssertEqual(css.modelIntermediate, full.modelIntermediate)
        XCTAssertEqual(css.hiddenIntermediate, css.mountedIntermediate)
        XCTAssertEqual(offscreen.domNodes, full.domNodes)
        XCTAssertEqual(offscreen.modelIntermediate, full.modelIntermediate)

        // Removing live nodes *after* creation reduces DOM, but leaves application-owned
        // records and payloads in memory. Actual React may subsequently re-mount the nodes.
        XCTAssertEqual(pruned.mountedIntermediate, 0)
        XCTAssertEqual(pruned.modelIntermediate, full.modelIntermediate)
        XCTAssertEqual(pruned.retainedPayloadBytes, full.retainedPayloadBytes)

        // Only an owned renderer which never constructs intermediate records meets
        // the strict "zero intermediate content in the phone" requirement.
        XCTAssertEqual(ownedFrontend.mountedIntermediate, 0)
        XCTAssertEqual(ownedFrontend.modelIntermediate, 0)
        XCTAssertEqual(ownedFrontend.retainedPayloadBytes, 0)
        XCTAssertLessThan(ownedFrontend.domNodes, full.domNodes)
        for snapshot in [full, css, offscreen, pruned, ownedFrontend] {
            XCTAssertEqual(snapshot.mountedFinal, 400)
            XCTAssertEqual(snapshot.actionButtons, 1)
            let data = try JSONEncoder().encode([
                "mode": snapshot.mode,
                "domNodes": String(snapshot.domNodes),
                "mountedIntermediate": String(snapshot.mountedIntermediate),
                "hiddenIntermediate": String(snapshot.hiddenIntermediate),
                "modelIntermediate": String(snapshot.modelIntermediate),
                "retainedPayloadBytes": String(snapshot.retainedPayloadBytes),
                "mountedFinal": String(snapshot.mountedFinal),
                "actionButtons": String(snapshot.actionButtons),
                "layoutMs": String(format: "%.1f", snapshot.layoutMs),
            ])
            print("RESULT_ONLY_WEBKIT_BENCH \(String(decoding: data, as: UTF8.self))")
        }
    }

    private func sample(_ mode: String) async throws -> Snapshot {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844),
                                configuration: config)
        if let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow }) {
            window.addSubview(webView)
        }
        let expectation = expectation(description: "WKWebView fixture loaded: \(mode)")
        let delegate = LoadDelegate(expectation)
        webView.navigationDelegate = delegate
        webView.loadHTMLString(Self.fixture(mode), baseURL: URL(string: "about:blank"))
        await fulfillment(of: [expectation], timeout: 35)
        if let error = delegate.navigationError { throw error }
        let encoded = try await webView.evaluateJavaScript(
            "JSON.stringify(window.__resultOnlyBenchmark())"
        ) as? String
        XCTAssertNotNil(encoded, "Fixture must evaluate in WebKit page world")
        defer {
            webView.stopLoading()
            webView.navigationDelegate = nil
            webView.removeFromSuperview()
        }
        return try JSONDecoder().decode(Snapshot.self,
                                         from: Data((encoded ?? "{}").utf8))
    }

    private static func fixture(_ mode: String) -> String {
        // Payload simulates expensive MCP/reasoning records retained by an app-level
        // React-like model. This is a controlled fixture, *not* the real ChatGPT runtime.
        // It deliberately gives CSS its best-case early insertion, before any nodes mount.
        let css: String
        switch mode {
        case "css_hidden":
            css = ".intermediate { display: none !important; animation: none !important; }"
        case "offscreen":
            css = ".turn { content-visibility: auto; contain-intrinsic-size: auto 140px; }"
        default:
            css = ""
        }
        return """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>body{font:14px -apple-system;margin:8px}.turn{border-bottom:1px solid #ccc}
        .final{padding:3px}.intermediate{padding:3px;animation:spin 1s infinite}
        @keyframes spin{from{opacity:.6}to{opacity:1}}
        \(css)</style></head>
        <body><main id="conversation"></main>
        <div id="permission"><button id="approve">Approve tool action</button></div>
        <script>
        (() => {
          const mode = '\(mode)';
          const model = [];
          const root = document.getElementById('conversation');
          const fragment = document.createDocumentFragment();
          const started = performance.now();
          const payload = 'MCP intermediate data '.repeat(100);
          for (let i = 0; i < 400; i++) {
            const turn = document.createElement('article');
            turn.className = 'turn';
            const user = document.createElement('p');
            user.className = 'user';
            user.textContent = 'user-' + i;
            turn.appendChild(user);
            model.push({kind:'user',value:'user-' + i});
            if (mode !== 'owned_final_only') {
              for (let j = 0; j < 6; j++) {
                model.push({kind:'intermediate',payload:payload});
                const item = document.createElement('section');
                item.className = 'intermediate';
                item.textContent = 'tool result ' + i + '/' + j;
                turn.appendChild(item);
              }
            }
            const finalNode = document.createElement('section');
            finalNode.className = 'final';
            finalNode.textContent = 'Final answer ' + i;
            turn.appendChild(finalNode);
            model.push({kind:'final',value:'Final answer ' + i});
            fragment.appendChild(turn);
          }
          root.appendChild(fragment);
          if (mode === 'dom_pruned') {
            document.querySelectorAll('.intermediate').forEach(x => x.remove());
          }
          const modelIntermediate = model.filter(x => x.kind === 'intermediate').length;
          window.__reactLikeModel = model;
          window.__resultOnlyBenchmark = () => {
            const first = performance.now();
            void document.body.offsetHeight; // force WebKit layout
            const layoutMs = performance.now() - first;
            const intermediate = [...document.querySelectorAll('.intermediate')];
            return {
              mode, domNodes: document.getElementsByTagName('*').length,
              mountedIntermediate: intermediate.length,
              hiddenIntermediate: intermediate.filter(
                x => getComputedStyle(x).display === 'none').length,
              modelIntermediate, retainedPayloadBytes: modelIntermediate * payload.length * 2,
              mountedFinal: document.querySelectorAll('.final').length,
              actionButtons: document.querySelectorAll('#approve').length,
              layoutMs: Math.round(layoutMs * 10) / 10,
            };
          };
        })();
        </script></body></html>
        """
    }
}
