import XCTest
import Foundation
import UniformTypeIdentifiers
@testable import ChatGPTWebOptimized

final class OptimizedDownloadTests: XCTestCase {
    private func temporaryStore() -> (URL, OptimizedDownloadStore) {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        return (base, OptimizedDownloadStore(root: base.appendingPathComponent("finished", isDirectory: true),
                                            staging: base.appendingPathComponent("staging", isDirectory: true)))
    }

    func testSafeFilenamePreservesExtensionAndUnicode() {
        XCTAssertEqual(OptimizedDownloadStore.safeFilename("报告.xlsx", mimeType: nil), "报告.xlsx")
        XCTAssertEqual(OptimizedDownloadStore.safeFilename("photo", mimeType: "image/png"), "photo.png")
        XCTAssertEqual(OptimizedDownloadStore.safeFilename("..", mimeType: "text/plain"), "download.txt")
        let name = OptimizedDownloadStore.safeFilename("../foo\\bar/报告\n.pdf", mimeType: nil)
        XCTAssertFalse(name.contains("/"))
        XCTAssertFalse(name.contains("\\"))
        XCTAssertFalse(name.contains("\n"))
        XCTAssertTrue(name.hasSuffix(".pdf"))
        let huge = OptimizedDownloadStore.safeFilename(String(repeating: "图", count: 300) + ".png", mimeType: nil)
        XCTAssertTrue(huge.hasSuffix(".png"))
        XCTAssertLessThan(huge.utf8.count, 255)
    }

    func testCompletedDownloadsPersistAndSameNameDoesNotOverwrite() throws {
        let (base, store) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: base) }
        let a = try store.destination(filename: "report.txt", mimeType: "text/plain")
        let b = try store.destination(filename: "report.txt", mimeType: "text/plain")
        try Data("first".utf8).write(to: a)
        try Data("second".utf8).write(to: b)
        XCTAssertTrue(store.completedFiles().isEmpty, "Partial files must not appear")
        let first = try store.commit(a)
        let second = try store.commit(b)
        XCTAssertEqual(first.lastPathComponent, "report.txt")
        XCTAssertEqual(second.lastPathComponent, "report.txt")
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try Data(contentsOf: first), Data("first".utf8))
        XCTAssertEqual(try Data(contentsOf: second), Data("second".utf8))
        let reopened = OptimizedDownloadStore(root: store.root, staging: store.staging)
        XCTAssertEqual(Set(reopened.completedFiles()), Set([first, second]))
        try reopened.remove(first)
        XCTAssertEqual(reopened.completedFiles(), [second])
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
    }

    func testFailureCleanupCannotDeleteCompletedOrUnrelatedFile() throws {
        let (base, store) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: base) }
        let completed = try store.destination(filename: "done.txt", mimeType: nil)
        try Data([1, 2, 3]).write(to: completed)
        let file = try store.commit(completed)
        let partial = try store.destination(filename: "partial.png", mimeType: nil)
        try Data([0]).write(to: partial)
        store.discardStaged(partial)
        store.discardStaged(file)
        XCTAssertFalse(FileManager.default.fileExists(atPath: partial.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertThrowsError(try store.remove(base.appendingPathComponent("unrelated.txt")))
        XCTAssertEqual(store.completedFiles(), [file])
    }

    func testDownloadRoutesAndHTTPResponsePolicy() {
        for raw in ["https://chatgpt.com/file", "http://example.com/file",
                    "blob:https://chatgpt.com/fixture", "data:text/plain,hello"] {
            XCTAssertTrue(OptimizedDownloadStore.supportsDownload(URL(string: raw)!))
        }
        for raw in ["javascript:alert(1)", "file:///private/test", "sandbox:/mnt/data/test"] {
            XCTAssertFalse(OptimizedDownloadStore.supportsDownload(URL(string: raw)!))
        }
        let url = URL(string: "https://chatgpt.com/file")!
        let png = URLResponse(url: url, mimeType: "image/png", expectedContentLength: 10, textEncodingName: nil)
        let pdf = URLResponse(url: url, mimeType: "application/pdf", expectedContentLength: 10, textEncodingName: nil)
        let html = URLResponse(url: url, mimeType: "text/html", expectedContentLength: 10, textEncodingName: nil)
        XCTAssertTrue(OptimizedDownloadStore.shouldDownloadResponse(png, canShow: true, mainFrame: true))
        XCTAssertTrue(OptimizedDownloadStore.shouldDownloadResponse(pdf, canShow: true, mainFrame: true))
        XCTAssertFalse(OptimizedDownloadStore.shouldDownloadResponse(png, canShow: true, mainFrame: false))
        XCTAssertFalse(OptimizedDownloadStore.shouldDownloadResponse(html, canShow: true, mainFrame: true))
        let attachment = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                         headerFields: ["Content-Disposition": "attachment; filename=report.xlsx"])!
        XCTAssertTrue(OptimizedDownloadStore.shouldDownloadResponse(attachment, canShow: true, mainFrame: true))
        XCTAssertTrue(OptimizedDownloadStore.acceptsResponse(attachment))
        let failed = HTTPURLResponse(url: url, statusCode: 403, httpVersion: nil, headerFields: nil)!
        XCTAssertFalse(OptimizedDownloadStore.acceptsResponse(failed))
        XCTAssertTrue(OptimizedDownloadStore.isImage(URL(fileURLWithPath: "/tmp/picture.png")))
        XCTAssertFalse(OptimizedDownloadStore.isImage(URL(fileURLWithPath: "/tmp/report.pdf")))
    }
}
