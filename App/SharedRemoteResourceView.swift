import Foundation
import SwiftUI
import SafariServices
import UIKit

/// Native in-app browser for already rendered public links. It never opens a
/// second ChatGPT account session on behalf of the PC Bridge.
struct STSafariPage: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let browser = SFSafariViewController(url: url)
        browser.dismissButtonStyle = .close
        return browser
    }
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

struct STNativeWebLink: View {
    let title: String
    let url: URL
    @State private var showing = false
    var body: some View {
        Button { showing = true } label: {
            Label(title.isEmpty ? url.host ?? "打开链接" : title, systemImage: "link")
                .font(.footnote)
        }
        .accessibilityIdentifier("shared.nativeLink")
        .sheet(isPresented: $showing) {
            STSafariPage(url: url).ignoresSafeArea()
        }
    }
}

private struct STDownloadedItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct STFileShareSheet: UIViewControllerRepresentable {
    let file: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [file], applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// Do not forward phone's Bridge key or PC cookies to third-party file hosts.
/// Redirects are allowed only to another public HTTP(S) address.
private final class STSafeFileRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSession,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(STResourcePolicy.publicURL(request.url?.absoluteString) == nil ? nil : request)
    }
}

struct STNativeFileLink: View {
    let title: String
    let url: URL
    @State private var preview = false
    @State private var downloading = false
    @State private var downloaded: STDownloadedItem?
    @State private var error: String?
    var body: some View {
        HStack(spacing: 12) {
            Button { preview = true } label: {
                Label(title.isEmpty ? "查看文件" : title, systemImage: "doc")
                    .font(.footnote).frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityIdentifier("shared.file.preview")
            if downloading {
                ProgressView().controlSize(.small).accessibilityIdentifier("shared.file.downloading")
            } else {
                Button {
                    Task { await download() }
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .accessibilityLabel("下载文件")
                .accessibilityIdentifier("shared.file.download")
            }
        }
        .padding(10)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
        .sheet(isPresented: $preview) { STSafariPage(url: url).ignoresSafeArea() }
        .sheet(item: $downloaded, onDismiss: {
            // The system share/save action copies the file; keep no permanent
            // archive or hidden cache in the app.
            if let file = completedFile { try? FileManager.default.removeItem(at: file) }
            completedFile = nil
        }) { STFileShareSheet(file: $0.url) }
        .alert("无法下载", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("知道了") { error = nil }
        } message: {
            Text(error ?? "当前地址无法直接下载，可以在 PC 网页查看原附件。")
        }
    }
    @State private var completedFile: URL?
    @MainActor private func download() async {
        guard !downloading else { return }
        downloading = true; defer { downloading = false }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 45
        config.timeoutIntervalForResource = 100
        let session = URLSession(configuration: config, delegate: STSafeFileRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        do {
            let (temporary, response) = try await session.download(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            let size = (try FileManager.default.attributesOfItem(atPath: temporary.path)[.size] as? NSNumber)?.int64Value ?? 0
            guard size > 0 && size <= 100 * 1024 * 1024 else { throw URLError(.dataLengthExceedsMaximum) }
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("MirrorDownloads", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let name = STResourcePolicy.downloadName(title.isEmpty ? response.suggestedFilename ?? "" : title, url: url)
            let destination = folder.appendingPathComponent(UUID().uuidString + "-" + name)
            try FileManager.default.moveItem(at: temporary, to: destination)
            completedFile = destination
            downloaded = STDownloadedItem(url: destination)
        } catch {
            self.error = "文件无法直接下载，请在 PC 查看原附件。\(error.localizedDescription)"
        }
    }
}
