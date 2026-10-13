import Foundation

var count = 0
func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
    count += 1
    guard condition() else { fatalError("FAILED: \(name)") }
}
expect(STResourcePolicy.publicURL("https://www.example.com/report.pdf") != nil, "ordinary HTTPS file")
expect(STResourcePolicy.publicURL("https://www.example.com/help") != nil, "ordinary HTTPS link")
expect(STResourcePolicy.publicURL("http://example.org/") != nil, "public HTTP link")
for blocked in ["sandbox:/mnt/data/secret.pdf", "blob:https://chatgpt.com/xyz",
                "javascript:alert(1)", "file:///private/document",
                "https://127.0.0.1/report", "https://192.168.1.4/file",
                "http://10.0.0.4/secret", "https://172.20.1.3/api",
                "https://localhost/file", "https://dev.local/file",
                "https://example.invalid/a", "https://user:pass@example.com/x"] {
    expect(STResourcePolicy.publicURL(blocked) == nil, "reject unsafe \(blocked)")
}
let file = URL(string: "https://www.example.com/report.pdf")!
expect(STResourcePolicy.downloadName("statement.pdf", url: file) == "statement.pdf", "retain file extension")
expect(!STResourcePolicy.downloadName("../../private\\secret.pdf", url: file).contains("/"), "strip directory separators")
expect(!STResourcePolicy.downloadName("a\\nb", url: file).contains("\n"), "strip control chars")
print("Native mirror link/file policy: \(count) assertions PASS")
