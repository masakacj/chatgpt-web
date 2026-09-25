import Foundation

struct UnifiedScriptPayload {
    let source: String
    let version: String
    let origin: String
}

final class UnifiedScriptStore {
    static let shared = UnifiedScriptStore()

    private let fileManager = FileManager.default
    private let requestTimeout: TimeInterval = 6

    private let repositoryOwner = "masakacj"
    private let repositoryName = "chatgpt-web"
    private let repositoryBranch = "main"

    private let scriptPath =
        "safari/chatgpt-safari.user.js"

    private let gestureScriptPath =
        "safari/chatgpt-ios-gestures.user.js"

    private struct RemoteText {
        let text: String
        let source: String
    }

    private enum RemoteSource: CaseIterable {
        case githubRaw
        case jsDelivr
        case jsDelivrFastly
        case githubAPI

        var label: String {
            switch self {
            case .githubRaw:
                return "github-raw"
            case .jsDelivr:
                return "jsdelivr"
            case .jsDelivrFastly:
                return "jsdelivr-fastly"
            case .githubAPI:
                return "github-api"
            }
        }
    }

    private init() {}

    var appVersion: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "0"
    }

    func bestLocalScript() -> UnifiedScriptPayload? {
        newest(
            cached: loadCachedScript(),
            bundled: loadBundledScript()
        )
    }

    func bestLocalGestureScript() -> UnifiedScriptPayload? {
        newest(
            cached: loadCachedGestureScript(),
            bundled: loadBundledGestureScript()
        )
    }

    func fetchLatest() async throws -> UnifiedScriptPayload {
        let remotes =
            await fetchAllRemoteTexts(
                path: scriptPath
            )

        let candidates =
            remotes.compactMap { remote
                -> UnifiedScriptPayload? in
                guard
                    let version =
                        scriptVersion(
                            in: remote.text
                        )
                else {
                    return nil
                }

                return UnifiedScriptPayload(
                    source: remote.text,
                    version: version,
                    origin:
                        "remote/" + remote.source
                )
            }

        guard
            let payload =
                newestRemotePayload(candidates)
        else {
            throw ScriptError.allSourcesFailed
        }

        try saveCachedScript(payload)
        return payload
    }

    func fetchLatestGestureScript()
        async throws -> UnifiedScriptPayload
    {
        let remotes =
            await fetchAllRemoteTexts(
                path: gestureScriptPath
            )

        let candidates =
            remotes.compactMap { remote
                -> UnifiedScriptPayload? in
                guard
                    let version =
                        gestureScriptVersion(
                            in: remote.text
                        )
                else {
                    return nil
                }

                return UnifiedScriptPayload(
                    source: remote.text,
                    version: version,
                    origin:
                        "remote/" + remote.source
                )
            }

        guard
            let payload =
                newestRemotePayload(candidates)
        else {
            throw ScriptError.allSourcesFailed
        }

        try saveCachedGestureScript(payload)
        return payload
    }

    func nativeBootstrap(
        scriptVersion: String,
        scriptOrigin: String,
        updateStatus: String,
        gestureVersion: String? = nil,
        gestureOrigin: String? = nil,
        gestureUpdateStatus: String? = nil
    ) -> String {
        var payload: [String: Any] = [
            "appVersion": appVersion,
            "scriptVersion": scriptVersion,
            "scriptOrigin": scriptOrigin,
            "updateStatus": updateStatus,
            "hotUpdate": true
        ]

        if let gestureVersion {
            payload["gestureVersion"] = gestureVersion
        }
        if let gestureOrigin {
            payload["gestureOrigin"] = gestureOrigin
        }
        if let gestureUpdateStatus {
            payload["gestureUpdateStatus"] =
                gestureUpdateStatus
        }

        guard
            let data =
                try? JSONSerialization.data(
                    withJSONObject: payload
                ),
            let json =
                String(data: data, encoding: .utf8)
        else {
            return """
            window.__CHATGPT_NATIVE__ = {
              hotUpdate: true
            };
            """
        }

        return "window.__CHATGPT_NATIVE__ = \(json);"
    }

    func runtimeStatusJavaScript(
        scriptVersion: String,
        scriptOrigin: String,
        updateStatus: String,
        gestureVersion: String? = nil,
        gestureOrigin: String? = nil,
        gestureUpdateStatus: String? = nil
    ) -> String {
        let bootstrap = nativeBootstrap(
            scriptVersion: scriptVersion,
            scriptOrigin: scriptOrigin,
            updateStatus: updateStatus,
            gestureVersion: gestureVersion,
            gestureOrigin: gestureOrigin,
            gestureUpdateStatus: gestureUpdateStatus
        )

        return """
        \(bootstrap)
        window.ChatGPTWeb?.setNativeStatus?.(
          window.__CHATGPT_NATIVE__
        );
        window.ChatGPTSafari?.setNativeStatus?.(
          window.__CHATGPT_NATIVE__
        );
        """
    }

    func scriptVersion(in source: String) -> String? {
        let metadata = match(
            pattern: #"(?m)^//\s*@version\s+([^\s]+)\s*$"#,
            in: source
        )

        let runtime = match(
            pattern: #"const\s+VERSION\s*=\s*['"]([^'"]+)['"]\s*;"#,
            in: source
        )

        guard
            let metadata,
            let runtime,
            metadata == runtime
        else {
            return nil
        }

        guard
            source.contains(
                "// @name         ChatGPT Web Unified"
            ),
            source.contains(
                "const GLOBAL_KEY = 'ChatGPTWeb';"
            )
        else {
            return nil
        }

        return metadata
    }

    func gestureScriptVersion(
        in source: String
    ) -> String? {
        let metadata = match(
            pattern: #"(?m)^//\s*@version\s+([^\s]+)\s*$"#,
            in: source
        )

        let runtime = match(
            pattern: #"const\s+VERSION\s*=\s*['"]([^'"]+)['"]\s*;"#,
            in: source
        )

        guard
            let metadata,
            let runtime,
            metadata == runtime
        else {
            return nil
        }

        guard
            source.contains(
                "// @name         ChatGPT Web iOS Gestures"
            ),
            source.contains(
                "const GLOBAL_KEY = 'ChatGPTIOSGestures';"
            )
        else {
            return nil
        }

        return metadata
    }

    private func newest(
        cached: UnifiedScriptPayload?,
        bundled: UnifiedScriptPayload?
    ) -> UnifiedScriptPayload? {
        switch (cached, bundled) {
        case let (.some(a), .some(b)):
            return isVersion(
                a.version,
                newerThan: b.version
            ) ? a : b

        case let (.some(a), .none):
            return a

        case let (.none, .some(b)):
            return b

        case (.none, .none):
            return nil
        }
    }

    private func loadCachedScript()
        -> UnifiedScriptPayload?
    {
        loadCached(
            at: cachedScriptURL,
            validator: scriptVersion
        )
    }

    private func loadCachedGestureScript()
        -> UnifiedScriptPayload?
    {
        loadCached(
            at: cachedGestureScriptURL,
            validator: gestureScriptVersion
        )
    }

    private func loadCached(
        at url: URL,
        validator: (String) -> String?
    ) -> UnifiedScriptPayload? {
        guard
            let data = try? Data(contentsOf: url),
            let source =
                String(data: data, encoding: .utf8),
            let version = validator(source)
        else {
            return nil
        }

        return UnifiedScriptPayload(
            source: source,
            version: version,
            origin: "cached"
        )
    }

    private func loadBundledScript()
        -> UnifiedScriptPayload?
    {
        loadBundled(
            candidates: bundledScriptCandidates(),
            validator: scriptVersion
        )
    }

    private func loadBundledGestureScript()
        -> UnifiedScriptPayload?
    {
        loadBundled(
            candidates: bundledGestureScriptCandidates(),
            validator: gestureScriptVersion
        )
    }

    private func loadBundled(
        candidates: [URL],
        validator: (String) -> String?
    ) -> UnifiedScriptPayload? {
        for url in candidates {
            guard
                let source =
                    try? String(
                        contentsOf: url,
                        encoding: .utf8
                    ),
                let version = validator(source)
            else {
                continue
            }

            return UnifiedScriptPayload(
                source: source,
                version: version,
                origin: "bundled"
            )
        }

        return nil
    }

    private func bundledScriptCandidates() -> [URL] {
        bundleCandidates(
            filename: "chatgpt-safari.user.js"
        )
    }

    private func bundledGestureScriptCandidates()
        -> [URL]
    {
        bundleCandidates(
            filename: "chatgpt-ios-gestures.user.js"
        )
    }

    private func bundleCandidates(
        filename: String
    ) -> [URL] {
        var result: [URL] = []

        let parts = filename.split(
            separator: ".",
            maxSplits: 1
        )

        if parts.count == 2,
           let url = Bundle.main.url(
               forResource: String(parts[0]),
               withExtension: String(parts[1])
           ) {
            result.append(url)
        }

        if let resourceURL = Bundle.main.resourceURL {
            result.append(
                resourceURL.appendingPathComponent(
                    filename
                )
            )
            result.append(
                resourceURL
                    .appendingPathComponent(
                        "safari",
                        isDirectory: true
                    )
                    .appendingPathComponent(filename)
            )
        }

        if let urls = Bundle.main.urls(
            forResourcesWithExtension: "js",
            subdirectory: nil
        ) {
            result.append(
                contentsOf: urls.filter {
                    $0.lastPathComponent == filename
                }
            )
        }

        var seen = Set<String>()

        return result.filter {
            seen.insert($0.path).inserted
        }
    }

    private var supportDirectory: URL {
        let base = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        return base.appendingPathComponent(
            "ChatGPTWebUnified",
            isDirectory: true
        )
    }

    private var cachedScriptURL: URL {
        supportDirectory.appendingPathComponent(
            "chatgpt-web-unified.user.js"
        )
    }

    private var cachedGestureScriptURL: URL {
        supportDirectory.appendingPathComponent(
            "chatgpt-ios-gestures.user.js"
        )
    }

    private func saveCachedScript(
        _ payload: UnifiedScriptPayload
    ) throws {
        try saveCached(
            payload,
            at: cachedScriptURL
        )
    }

    private func saveCachedGestureScript(
        _ payload: UnifiedScriptPayload
    ) throws {
        try saveCached(
            payload,
            at: cachedGestureScriptURL
        )
    }

    private func saveCached(
        _ payload: UnifiedScriptPayload,
        at url: URL
    ) throws {
        try fileManager.createDirectory(
            at: supportDirectory,
            withIntermediateDirectories: true
        )

        try Data(payload.source.utf8).write(
            to: url,
            options: .atomic
        )
    }

    private func newestRemotePayload(
        _ candidates: [UnifiedScriptPayload]
    ) -> UnifiedScriptPayload? {
        guard var best = candidates.first else {
            return nil
        }

        for candidate in candidates.dropFirst() {
            if isVersion(
                candidate.version,
                newerThan: best.version
            ) {
                best = candidate
            }
        }

        return best
    }

    private func fetchAllRemoteTexts(
        path: String
    ) async -> [RemoteText] {
        await withTaskGroup(
            of: RemoteText?.self
        ) { group in
            for source in RemoteSource.allCases {
                group.addTask {
                    await self.fetchRemoteText(
                        path: path,
                        source: source
                    )
                }
            }

            var results: [RemoteText] = []

            for await value in group {
                if let value {
                    results.append(value)
                }
            }

            return results
        }
    }

    private func fetchRemoteText(
        path: String,
        source: RemoteSource
    ) async -> RemoteText? {
        guard
            let url = remoteURL(
                path: path,
                source: source
            )
        else {
            return nil
        }

        var request = URLRequest(
            url: cacheBusted(url),
            timeoutInterval: requestTimeout
        )

        request.cachePolicy =
            .reloadIgnoringLocalCacheData

        request.setValue(
            "no-cache",
            forHTTPHeaderField: "Cache-Control"
        )

        request.setValue(
            "no-cache",
            forHTTPHeaderField: "Pragma"
        )

        request.setValue(
            "ChatGPTWeb-iOS/" + appVersion,
            forHTTPHeaderField: "User-Agent"
        )

        if source == .githubAPI {
            request.setValue(
                "application/vnd.github.raw+json",
                forHTTPHeaderField: "Accept"
            )
        }

        do {
            let (data, response) =
                try await URLSession.shared.data(
                    for: request
                )

            try validateHTTP(response)

            guard
                let text =
                    String(
                        data: data,
                        encoding: .utf8
                    ),
                !text.isEmpty
            else {
                return nil
            }

            return RemoteText(
                text: text,
                source: source.label
            )
        } catch {
            return nil
        }
    }

    private func remoteURL(
        path: String,
        source: RemoteSource
    ) -> URL? {
        let encodedPath =
            path.addingPercentEncoding(
                withAllowedCharacters:
                    .urlPathAllowed
            ) ?? path

        switch source {
        case .githubRaw:
            return URL(
                string:
                    "https://raw.githubusercontent.com/" +
                    repositoryOwner + "/" +
                    repositoryName + "/" +
                    repositoryBranch + "/" +
                    encodedPath
            )

        case .jsDelivr:
            return URL(
                string:
                    "https://cdn.jsdelivr.net/gh/" +
                    repositoryOwner + "/" +
                    repositoryName + "@" +
                    repositoryBranch + "/" +
                    encodedPath
            )

        case .jsDelivrFastly:
            return URL(
                string:
                    "https://fastly.jsdelivr.net/gh/" +
                    repositoryOwner + "/" +
                    repositoryName + "@" +
                    repositoryBranch + "/" +
                    encodedPath
            )

        case .githubAPI:
            var components = URLComponents()
            components.scheme = "https"
            components.host = "api.github.com"
            components.path =
                "/repos/" +
                repositoryOwner + "/" +
                repositoryName +
                "/contents/" + path
            components.queryItems = [
                URLQueryItem(
                    name: "ref",
                    value: repositoryBranch
                )
            ]
            return components.url
        }
    }

    private func validateHTTP(
        _ response: URLResponse
    ) throws {
        guard
            let http = response as? HTTPURLResponse,
            (200..<300).contains(http.statusCode)
        else {
            throw ScriptError.badResponse
        }
    }

    private func cacheBusted(_ url: URL) -> URL {
        guard
            var components = URLComponents(
                url: url,
                resolvingAgainstBaseURL: false
            )
        else {
            return url
        }

        components.queryItems = [
            URLQueryItem(
                name: "t",
                value: String(
                    Int(Date().timeIntervalSince1970)
                )
            )
        ]

        return components.url ?? url
    }

    private func match(
        pattern: String,
        in source: String
    ) -> String? {
        guard
            let regex =
                try? NSRegularExpression(
                    pattern: pattern
                ),
            let result =
                regex.firstMatch(
                    in: source,
                    range: NSRange(
                        source.startIndex...,
                        in: source
                    )
                ),
            result.numberOfRanges > 1,
            let range =
                Range(
                    result.range(at: 1),
                    in: source
                )
        else {
            return nil
        }

        return String(source[range])
    }

    private func isVersion(
        _ lhs: String,
        newerThan rhs: String
    ) -> Bool {
        let a =
            lhs.split(separator: ".")
                .map { Int($0) ?? 0 }

        let b =
            rhs.split(separator: ".")
                .map { Int($0) ?? 0 }

        let count = max(a.count, b.count)

        for index in 0..<count {
            let av =
                index < a.count ? a[index] : 0

            let bv =
                index < b.count ? b[index] : 0

            if av != bv {
                return av > bv
            }
        }

        return false
    }

    enum ScriptError: Error {
        case badResponse
        case invalidRemoteScript
        case invalidRemoteGestureScript
        case allSourcesFailed
    }
}
