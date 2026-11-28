import Foundation
import SwiftUI
import UIKit
import Photos
import UniformTypeIdentifiers

/// WebKit keeps its existing website data store and proxy. Only completed
/// local files are exposed to the native export UI.
struct OptimizedDownloadStore {
    let root: URL
    let staging: URL

    init(root: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("OptimizerDownloads", isDirectory: true),
         staging: URL = FileManager.default.temporaryDirectory
        .appendingPathComponent("OptimizerDownloadStaging", isDirectory: true)) {
        self.root = root
        self.staging = staging
    }

    static func supportsDownload(_ url: URL) -> Bool {
        ["https", "http", "blob", "data"].contains(url.scheme?.lowercased() ?? "")
    }

    static func isInlineDownload(_ url: URL) -> Bool {
        ["blob", "data"].contains(url.scheme?.lowercased() ?? "")
    }

    static func acceptsResponse(_ response: URLResponse) -> Bool {
        guard let http = response as? HTTPURLResponse else { return true }
        return (200...299).contains(http.statusCode)
    }

    static func shouldDownloadResponse(_ response: URLResponse,
                                       canShow: Bool, mainFrame: Bool) -> Bool {
        let disposition = (response as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "Content-Disposition")?.lowercased() ?? ""
        let mime = response.mimeType?.lowercased() ?? ""
        return disposition.contains("attachment") || !canShow ||
            (mainFrame && (mime.hasPrefix("image/") || mime == "application/pdf"))
    }

    static func safeFilename(_ suggested: String, mimeType: String?) -> String {
        let forbidden = CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "/\\:"))
        var name = suggested.components(separatedBy: forbidden).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        if name.isEmpty { name = "download" }
        let supplied = (name as NSString).pathExtension
        var ext = supplied.utf8.count <= 16 ? supplied : ""
        if ext.isEmpty, let mimeType {
            ext = UTType(mimeType: mimeType)?.preferredFilenameExtension ?? ""
        }
        var stem = String((supplied.isEmpty ? name : (name as NSString).deletingPathExtension).prefix(180))
        while stem.utf8.count > 180 { stem.removeLast() }
        if stem.isEmpty { stem = "download" }
        return stem + (ext.isEmpty ? "" : "." + ext)
    }

    func destination(filename: String, mimeType: String?) throws -> URL {
        let directory = staging.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(Self.safeFilename(filename, mimeType: mimeType))
    }

    func commit(_ url: URL) throws -> URL {
        let source = url.deletingLastPathComponent()
        guard source.deletingLastPathComponent().standardizedFileURL == staging.standardizedFileURL,
              UUID(uuidString: source.lastPathComponent) != nil,
              try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        let manager = FileManager.default
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        let directory = root.appendingPathComponent(source.lastPathComponent, isDirectory: true)
        try manager.moveItem(at: source, to: directory)
        return directory.appendingPathComponent(url.lastPathComponent)
    }

    func discardStaged(_ url: URL) {
        let parent = url.deletingLastPathComponent()
        guard parent.deletingLastPathComponent().standardizedFileURL == staging.standardizedFileURL,
              UUID(uuidString: parent.lastPathComponent) != nil else { return }
        try? FileManager.default.removeItem(at: parent)
    }

    func completedFiles() -> [URL] {
        let manager = FileManager.default
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .creationDateKey]
        let directories = (try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey],
                                                            options: [.skipsHiddenFiles])) ?? []
        return directories.flatMap { directory -> [(URL, Date)] in
            guard UUID(uuidString: directory.lastPathComponent) != nil,
                  (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return [] }
            return ((try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys),
                                                       options: [.skipsHiddenFiles])) ?? []).compactMap {
                guard let values = try? $0.resourceValues(forKeys: keys),
                      values.isRegularFile == true else { return nil }
                return ($0, values.creationDate ?? .distantPast)
            }
        }.sorted { $0.1 > $1.1 }.map { $0.0 }
    }

    func remove(_ url: URL) throws {
        let parent = url.deletingLastPathComponent()
        guard parent.deletingLastPathComponent().standardizedFileURL == root.standardizedFileURL,
              UUID(uuidString: parent.lastPathComponent) != nil else { throw CocoaError(.fileWriteInvalidFileName) }
        try FileManager.default.removeItem(at: parent)
    }

    static func isImage(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true
    }
}

private struct ExportSelection: Identifiable {
    let url: URL
    var id: URL { url }
}

private struct OptimizedFilesExporter: UIViewControllerRepresentable {
    let url: URL
    let finished: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(finished: finished) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let finished: (Bool) -> Void
        init(finished: @escaping (Bool) -> Void) { self.finished = finished }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            finished(!urls.isEmpty)
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { finished(false) }
    }
}

struct OptimizedDownloadsView: View {
    @ObservedObject var model: OptimizedAppModel
    @Environment(\.dismiss) private var dismiss
    @State private var exporting: ExportSelection?
    @State private var photoBusy: URL?
    @State private var result: String?
    @State private var deleting: ExportSelection?

    var body: some View {
        NavigationStack {
            List {
                if let notice = result ?? model.downloadNotice {
                    Text(notice).font(.footnote).accessibilityIdentifier("downloads.feedback")
                }
                if model.downloads.isEmpty {
                    Text("暂无已完成的下载。点击网页原有下载按钮即可下载。")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.downloads, id: \.self) { file in
                    VStack(alignment: .leading, spacing: 10) {
                        Label(file.lastPathComponent, systemImage: OptimizedDownloadStore.isImage(file) ? "photo" : "doc")
                            .font(.headline)
                            .accessibilityIdentifier("downloads.filename")
                        HStack(spacing: 16) {
                            Button("保存到文件") { exporting = ExportSelection(url: file) }
                                .accessibilityIdentifier("downloads.save.files")
                            if OptimizedDownloadStore.isImage(file) {
                                Button(photoBusy == file ? "正在保存…" : "保存到相册") { savePhoto(file) }
                                    .disabled(photoBusy != nil)
                                    .accessibilityIdentifier("downloads.save.photo")
                            }
                            ShareLink(item: file) { Image(systemName: "square.and.arrow.up") }
                                .accessibilityLabel("分享文件")
                            Spacer(minLength: 0)
                            Button(role: .destructive) { deleting = ExportSelection(url: file) } label: {
                                Image(systemName: "trash")
                            }.accessibilityLabel("删除本地下载")
                                .disabled(photoBusy != nil)
                        }.font(.subheadline).buttonStyle(.borderless)
                    }.padding(.vertical, 4)
                }
            }
            .navigationTitle("下载")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }.accessibilityIdentifier("downloads.done")
                        .disabled(photoBusy != nil)
                }
            }
            .sheet(item: $exporting) { selection in
                OptimizedFilesExporter(url: selection.url) { saved in
                    exporting = nil
                    if saved { result = "已保存到文件" }
                }
            }
            .alert("删除 App 内的下载副本？", isPresented: Binding(
                get: { deleting != nil }, set: { if !$0 { deleting = nil } }
            )) {
                Button("取消", role: .cancel) { deleting = nil }
                Button("删除", role: .destructive) {
                    guard let file = deleting?.url else { return }
                    deleting = nil
                    model.removeDownload(file)
                    result = nil
                }
            } message: { Text("已导出到文件或相册的副本不受影响。") }
            .interactiveDismissDisabled(photoBusy != nil)
            .onChange(of: model.downloadEvent) { _, _ in result = nil }
        }
    }

    private func savePhoto(_ file: URL) {
        guard photoBusy == nil else { return }
        photoBusy = file
        result = nil
        Task { @MainActor in
            defer { photoBusy = nil }
            let access = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard access == .authorized || access == .limited else {
                result = "未获得添加照片权限，可在系统设置中允许，或保存到文件。"
                return
            }
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetCreationRequest.forAsset().addResource(with: .photo, fileURL: file, options: nil)
                }
                result = "已保存到相册"
            } catch {
                result = "相册不支持此图片或保存失败，仍可保存原文件。"
            }
        }
    }
}
