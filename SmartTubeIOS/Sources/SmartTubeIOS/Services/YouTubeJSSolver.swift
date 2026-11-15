import Foundation
import JavaScriptCore
import SmartTubeIOSCore
import os

private let solverLog = Logger(subsystem: appSubsystem, category: "JSSolver")

/// Solves YouTube `n` (throttling) and `signatureCipher` challenges on-device with
/// JavaScriptCore, using yt-dlp's EJS solver bundled as `yt.solver.lib.min.js` +
/// `yt.solver.core.min.js`.
///
/// Works on every platform, including tvOS: no WebKit, no external process, no server.
/// Verified against jit-less JSC: output matches yt-dlp/Node byte-for-byte.
///
/// Cost: the first solve for a player version preprocesses base.js (~1 s on a desktop
/// CPU without JIT; expect a few seconds on Apple TV). The preprocessed player is cached
/// on disk per version, so later solves (and later launches) take ~20 ms.
public actor YouTubeJSSolver: StreamURLDeciphering {
    public static let shared = YouTubeJSSolver()

    /// Registers the shared solver for every `InnerTubeAPI` instance and warms it in the
    /// background so the first video doesn't wait on base.js download + preprocessing.
    /// Call once at launch.
    public static func install() {
        StreamURLDecipherRegistry.current = shared
        Task.detached(priority: .utility) { _ = await shared.signatureTimestamp() }
    }

    /// How long a resolved player version is trusted before checking for a newer one.
    private static let versionTTL: TimeInterval = 3600
    private static let safariUA =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.3 Safari/605.1.15"

    private struct PlayerSource: Sendable {
        let version: String
        let sts: Int?
        /// Preprocessed player (from disk cache) or raw base.js.
        let code: String
        let isPreprocessed: Bool
    }

    private enum LoadOutcome: Sendable {
        case unchanged
        case loaded(PlayerSource)
        case failed
    }

    private var context: JSContext?
    private var contextVersion: String?
    private var contextSTS: Int?
    private var checkedAt: Date?
    private var inFlight: Task<LoadOutcome, Never>?
    private var nCache: [String: String] = [:]
    private var sigCache: [String: String] = [:]

    // MARK: - StreamURLDeciphering

    public func signatureTimestamp() async -> Int? {
        _ = await readyContext()
        return contextSTS
    }

    // `n` mirrors YouTube's query-parameter name (see StreamURLDeciphering).
    // swiftlint:disable:next identifier_name
    public func solve(n: Set<String>, sig: Set<String>) async -> StreamChallengeSolutions {
        let ctx = await readyContext()

        var result = StreamChallengeSolutions()
        for key in n { if let solved = nCache[key] { result.n[key] = solved } }
        for key in sig { if let solved = sigCache[key] { result.sig[key] = solved } }
        let missingN = n.subtracting(result.n.keys)
        let missingSig = sig.subtracting(result.sig.keys)
        guard let ctx, !missingN.isEmpty || !missingSig.isEmpty else { return result }

        let solved = run(ctx, n: missingN, sig: missingSig)
        nCache.merge(solved.n) { _, new in new }
        sigCache.merge(solved.sig) { _, new in new }
        result.n.merge(solved.n) { _, new in new }
        result.sig.merge(solved.sig) { _, new in new }
        return result
    }

    // MARK: - Context lifecycle

    private func readyContext() async -> JSContext? {
        if let context, let checkedAt, Date().timeIntervalSince(checkedAt) < Self.versionTTL {
            return context
        }
        let task: Task<LoadOutcome, Never>
        if let inFlight {
            task = inFlight
        } else {
            let known = contextVersion
            task = Task.detached(priority: .userInitiated) { await Self.loadPlayerSource(currentVersion: known) }
            inFlight = task
        }
        let outcome = await task.value
        if inFlight == task { inFlight = nil }

        switch outcome {
        case .unchanged:
            checkedAt = Date()
            return context
        case .failed:
            // Keep using a stale context rather than failing; retry on next call if we have none.
            if context != nil { checkedAt = Date() }
            return context
        case .loaded(let source):
            if source.version == contextVersion, let context {
                checkedAt = Date()
                return context
            }
            guard let ctx = buildContext(source) else { return context }
            context = ctx
            contextVersion = source.version
            contextSTS = source.sts
            checkedAt = Date()
            nCache.removeAll()
            sigCache.removeAll()
            solverLog.notice("player \(source.version, privacy: .public) ready (sts=\(source.sts ?? -1))")
            return ctx
        }
    }

    private func buildContext(_ source: PlayerSource) -> JSContext? {
        guard let lib = Self.bundledScript("yt.solver.lib.min"),
            let core = Self.bundledScript("yt.solver.core.min")
        else {
            solverLog.error("EJS solver scripts missing from bundle")
            return nil
        }
        guard let ctx = JSContext() else { return nil }
        ctx.exceptionHandler = { _, exception in
            solverLog.error("JS exception: \(exception?.toString() ?? "nil", privacy: .public)")
        }
        ctx.evaluateScript(lib)
        ctx.evaluateScript("var meriyah = lib.meriyah; var astring = lib.astring;")
        ctx.evaluateScript(core)
        guard ctx.objectForKeyedSubscript("jsc")?.isObject == true else {
            solverLog.error("EJS solver failed to load (jsc undefined)")
            return nil
        }

        if source.isPreprocessed {
            ctx.setObject(source.code, forKeyedSubscript: "__ytPre" as NSString)
            return ctx
        }

        let start = Date()
        ctx.setObject(source.code, forKeyedSubscript: "__ytPlayer" as NSString)
        let pre = ctx.evaluateScript(
            """
            (function () {
              var r = jsc({ type: 'player', player: __ytPlayer, output_preprocessed: true, requests: [] });
              globalThis.__ytPlayer = undefined;
              globalThis.__ytPre = r.preprocessed_player;
              return r.preprocessed_player;
            })()
            """)
        guard let pre, pre.isString, let preprocessed = pre.toString() else {
            solverLog.error("preprocessing player \(source.version, privacy: .public) failed")
            return nil
        }
        let ms = Int(Date().timeIntervalSince(start) * 1000)
        solverLog.notice("preprocessed player \(source.version, privacy: .public) in \(ms) ms")
        Self.writeCache(version: source.version, sts: source.sts, preprocessed: preprocessed)
        return ctx
    }

    // swiftlint:disable:next identifier_name
    private func run(_ ctx: JSContext, n: Set<String>, sig: Set<String>) -> StreamChallengeSolutions {
        var types: [String] = []
        var requests: [[String: Any]] = []
        if !n.isEmpty {
            types.append("n")
            requests.append(["type": "n", "challenges": Array(n)])
        }
        if !sig.isEmpty {
            types.append("sig")
            requests.append(["type": "sig", "challenges": Array(sig)])
        }
        guard let reqData = try? JSONSerialization.data(withJSONObject: requests),
            let reqJSON = String(data: reqData, encoding: .utf8)
        else { return .empty }

        ctx.setObject(reqJSON, forKeyedSubscript: "__ytReq" as NSString)
        let out = ctx.evaluateScript(
            "JSON.stringify(jsc({ type: 'preprocessed', preprocessed_player: __ytPre, requests: JSON.parse(__ytReq) }))"
        )
        guard let out, out.isString, let outData = out.toString()?.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: outData) as? [String: Any],
            let responses = obj["responses"] as? [[String: Any]]
        else {
            solverLog.error("solver returned no result")
            return .empty
        }

        var result = StreamChallengeSolutions()
        for (type, response) in zip(types, responses) {
            guard response["type"] as? String == "result", let data = response["data"] as? [String: String] else {
                let err = (response["error"] as? String)?.prefix(300) ?? "?"
                solverLog.error("\(type, privacy: .public) solve failed: \(err, privacy: .public)")
                continue
            }
            // yt-dlp treats "enhanced_except_…" / empty output as a failed n transform.
            let valid = data.filter { !$0.value.isEmpty && !$0.value.hasPrefix("enhanced_except") }
            if type == "n" { result.n = valid } else { result.sig = valid }
        }
        return result
    }

    // MARK: - Player source (network + disk cache)

    private static func loadPlayerSource(currentVersion: String?) async -> LoadOutcome {
        guard let version = await fetchPlayerVersion() else {
            solverLog.error("could not determine player version")
            return .failed
        }
        if version == currentVersion { return .unchanged }
        if let cached = readCache(version: version) { return .loaded(cached) }

        guard
            let url = URL(string: "https://www.youtube.com/s/player/\(version)/player_es6.vflset/en_US/base.js")
        else { return .failed }
        var req = URLRequest(url: url)
        req.setValue(safariUA, forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 20
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
            (resp as? HTTPURLResponse)?.statusCode == 200,
            let js = String(data: data, encoding: .utf8)
        else {
            solverLog.error("base.js download failed for \(version, privacy: .public)")
            return .failed
        }
        solverLog.notice("downloaded base.js \(version, privacy: .public) (\(data.count) bytes)")
        return .loaded(PlayerSource(version: version, sts: extractSTS(from: js), code: js, isPreprocessed: false))
    }

    private static func fetchPlayerVersion() async -> String? {
        for page in ["https://www.youtube.com/iframe_api", "https://www.youtube.com/"] {
            guard let url = URL(string: page) else { continue }
            var req = URLRequest(url: url)
            req.setValue(safariUA, forHTTPHeaderField: "User-Agent")
            req.setValue("SOCS=CAI", forHTTPHeaderField: "Cookie")
            req.timeoutInterval = 10
            guard let (data, _) = try? await URLSession.shared.data(for: req),
                let text = String(data: data, encoding: .utf8)
            else { continue }
            // Matches both /s/player/abcd1234/ and the escaped player\/abcd1234\/ in iframe_api.
            if let version = firstMatch(#"player\\?/([0-9a-f]{8})\\?/"#, in: text) { return version }
        }
        return nil
    }

    static func extractSTS(from js: String) -> Int? {
        firstMatch(#"signatureTimestamp[=:](\d+)"#, in: js).flatMap(Int.init)
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
            let range = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[range])
    }

    private static func bundledScript(_ name: String) -> String? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "js") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    // MARK: Disk cache — Caches/ejs-solver-<EJS>/<version>.pre.js + <version>.sts

    /// Bump when replacing the bundled yt.solver.*.min.js: the preprocessed format may change.
    private static let bundledEJSVersion = "0.8.0"

    private static var cacheDir: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("ejs-solver-\(bundledEJSVersion)", isDirectory: true)
    }

    private static func readCache(version: String) -> PlayerSource? {
        guard let dir = cacheDir,
            let pre = try? String(contentsOf: dir.appendingPathComponent("\(version).pre.js"), encoding: .utf8)
        else { return nil }
        let sts = (try? String(contentsOf: dir.appendingPathComponent("\(version).sts"), encoding: .utf8))
            .flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        solverLog.notice("using cached preprocessed player \(version, privacy: .public)")
        return PlayerSource(version: version, sts: sts, code: pre, isPreprocessed: true)
    }

    private static func writeCache(version: String, sts: Int?, preprocessed: String) {
        guard let dir = cacheDir else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        // Only the current player version is useful; drop older ones.
        for old in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] where !old.hasPrefix(version) {
            try? fm.removeItem(at: dir.appendingPathComponent(old))
        }
        try? preprocessed.write(to: dir.appendingPathComponent("\(version).pre.js"), atomically: true, encoding: .utf8)
        if let sts {
            try? String(sts).write(to: dir.appendingPathComponent("\(version).sts"), atomically: true, encoding: .utf8)
        }
    }
}
