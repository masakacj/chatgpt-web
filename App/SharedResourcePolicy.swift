import Foundation

/// Read-only, browser-independent checks for URLs already present in the
/// bound PC page. No PC cookies, Bridge pairing keys or arbitrary URL fetching.
enum STResourcePolicy {
    static func publicURL(_ raw: String?) -> URL? {
        guard let raw, raw.count <= 2048, let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(), ["https", "http"].contains(scheme),
              url.user == nil, url.password == nil,
              let host = url.host?.lowercased(), host.contains("."),
              host != "localhost", !host.hasSuffix(".localhost"),
              !host.hasSuffix(".local"), !host.hasSuffix(".internal"),
              !host.hasSuffix(".test"), !host.hasSuffix(".invalid"),
              !host.hasPrefix("127."), !host.hasPrefix("10."),
              !host.hasPrefix("192.168."), !host.hasPrefix("169.254."),
              !host.hasPrefix("172.16."), !host.hasPrefix("172.17."),
              !host.hasPrefix("172.18."), !host.hasPrefix("172.19."),
              !host.hasPrefix("172.2"), !host.hasPrefix("172.30."),
              !host.hasPrefix("172.31."), host != "0.0.0.0",
              host != "::1", !host.hasPrefix("fc"), !host.hasPrefix("fd") else { return nil }
        return url
    }

    static func downloadName(_ title: String, url: URL) -> String {
        let original = title.isEmpty ? url.lastPathComponent : title
        let cleaned = original.replacingOccurrences(of: #"[\/\\:\x00-\x1f]"#,
                                                     with: "_", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String((cleaned.isEmpty || cleaned == "." || cleaned == ".." ? "下载文件" : cleaned).prefix(110))
    }
}
