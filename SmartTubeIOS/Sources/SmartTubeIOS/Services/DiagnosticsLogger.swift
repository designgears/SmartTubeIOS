import Foundation
import SmartTubeIOSCore
import os

/// Logs to `os.Logger` and keeps a **local, on-device** diagnostic trail (replaces Firebase
/// Crashlytics — nothing leaves the device):
///
/// - `.notice` / `.error` lines become breadcrumbs: kept in a ring buffer and appended to
///   `session.log`. On launch the previous session's log is kept as `previous-session.log`,
///   so after a crash the lead-up is still on disk.
/// - Events (non-fatals, slow loads, wrong video, playback failures, user-requested reports)
///   are written as `report-<time>-<domain>.txt` with context keys + recent breadcrumbs.
///   The newest `DiagnosticsStore.maxReports` are kept.
/// - Uncaught Objective-C exceptions are written as a `SmartTube.Crash` report.
///   Signal crashes (Swift traps, EXC_BAD_ACCESS) still land in the system's own crash logs.
///
/// Files live in `DiagnosticsLogger.directory` (Caches on tvOS, Application Support elsewhere).
/// `.debug` entries are only written to `os.log`.
public struct DiagnosticsLogger: Sendable {

    /// #92: set once from the app entry point's init(), before any logging, from
    /// `AppSettings.disableAnalytics`. When `false`, nothing is written to disk.
    public nonisolated(unsafe) static var isEnabled = true

    /// Short identifier (8 hex chars) generated once per app session. Shown in the Stats for
    /// Nerds overlay and stamped into every report so the two can be matched up.
    static let sessionReportID: String = {
        let raw = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        return String(raw.prefix(8)).uppercased()
    }()

    /// Where session logs and reports are written.
    public static var directory: URL? { DiagnosticsStore.shared.directory }

    /// Rotates the session log and installs the uncaught-exception handler.
    /// Call once at launch, after setting `isEnabled`.
    public static func startSession() {
        guard isEnabled else { return }
        DiagnosticsStore.shared.startSession(reportID: sessionReportID)
    }

    private let logger: Logger
    private let category: String

    init(subsystem: String = appSubsystem, category: String) {
        logger = Logger(subsystem: subsystem, category: category)
        self.category = category
    }

    func notice(_ message: @autoclosure () -> String) {
        let msg = message()
        logger.notice("\(msg, privacy: .public)")
        guard Self.isEnabled else { return }
        DiagnosticsStore.shared.breadcrumb("[\(category)] \(msg)")
    }

    func error(_ message: @autoclosure () -> String) {
        let msg = message()
        logger.error("\(msg, privacy: .public)")
        guard Self.isEnabled else { return }
        DiagnosticsStore.shared.breadcrumb("[ERR][\(category)] \(msg)")
    }

    func debug(_ message: @autoclosure () -> String) {
        let msg = message()
        logger.debug("\(msg, privacy: .public)")
        // Not persisted — too verbose.
    }

    /// Records a non-fatal error (with extra context keys) as a local report.
    func recordNonFatal(_ error: Error, userInfo: [String: String] = [:]) {
        let nsError = error as NSError
        let msg = "[\(category)] \(nsError.domain)(\(nsError.code)): \(nsError.localizedDescription)"
        logger.error("\(msg, privacy: .public)")
        guard Self.isEnabled else { return }
        let store = DiagnosticsStore.shared
        store.breadcrumb(msg)
        for (key, value) in userInfo { store.setContext(key, value) }
        store.writeReport(domain: nsError.domain, code: nsError.code, summary: nsError.localizedDescription)
    }

    /// Stamps the video currently being loaded into the context of later reports.
    static func setVideoContext(id: String, title: String) {
        guard isEnabled else { return }
        let store = DiagnosticsStore.shared
        store.setContext("active_video_id", id)
        store.setContext("active_video_title", String(title.prefix(120)))
    }

    /// Stamps the video the user *intended* to play (earliest user-intent signal), so a
    /// report can show whether the wrong video was loaded.
    static func setIntendedVideo(id: String, title: String) {
        guard isEnabled else { return }
        let store = DiagnosticsStore.shared
        store.setContext("intended_video_id", id)
        store.setContext("intended_video_title", String(title.prefix(120)))
        store.setContext("intended_video_tap_time", Date().formatted(.iso8601))
    }

    /// Saves a user-requested diagnostic report (Settings → About).
    static func sendDiagnosticReport() {
        guard isEnabled else { return }
        let store = DiagnosticsStore.shared
        store.setContext("report_id", sessionReportID)
        store.breadcrumb("[Diagnostic] User-requested diagnostic report — report_id=\(sessionReportID)")
        store.writeReport(
            domain: "SmartTube.UserDiagnostic", code: 0,
            summary: "User-requested diagnostic report (ID: \(sessionReportID))")
    }

    /// Records a report when time-to-first-frame exceeds the slow-load threshold.
    static func recordSlowVideoLoad(
        videoId: String,
        elapsedMs: Int,
        streamType: String,
        hasError: Bool,
        errorDescription: String? = nil
    ) {
        guard isEnabled else { return }
        let store = DiagnosticsStore.shared
        store.setContext("slow_load_video_id", videoId)
        store.setContext("slow_load_ttff_ms", String(elapsedMs))
        store.setContext("slow_load_stream_type", streamType)
        store.setContext("slow_load_has_error", String(hasError))
        if let errorDescription { store.setContext("slow_load_error_desc", errorDescription) }
        store.breadcrumb("[SlowLoad] videoId=\(videoId) ttff=\(elapsedMs)ms stream=\(streamType) hasError=\(hasError)")
        store.writeReport(
            domain: "SmartTube.SlowLoad", code: 4001, summary: "Slow video load: \(elapsedMs)ms (\(streamType))")
    }

    /// Records a report when playback fails and the error is shown to the user.
    static func sendAutoPlaybackDiagnostic() {
        guard isEnabled else { return }
        let store = DiagnosticsStore.shared
        store.setContext("trigger", "auto")
        store.breadcrumb("[AutoDiagnostic] Playback failure — see context and breadcrumbs.")
        store.writeReport(
            domain: "SmartTube.AutoDiagnostic", code: 1, summary: "Playback failure — see session breadcrumbs")
    }

    /// Records a report when the video that reached readyToPlay is not the one intended.
    static func sendWrongVideoReport(
        intendedId: String,
        intendedTitle: String,
        activeId: String,
        activeTitle: String
    ) {
        let msg =
            "[WrongVideo] intended=\(intendedId) (\(intendedTitle.prefix(60))) active=\(activeId) (\(activeTitle.prefix(60)))"
        Logger(subsystem: appSubsystem, category: "WrongVideo").error("\(msg, privacy: .public)")
        guard isEnabled else { return }
        let store = DiagnosticsStore.shared
        store.setContext("wv_intended_id", intendedId)
        store.setContext("wv_intended_title", intendedTitle)
        store.setContext("wv_active_id", activeId)
        store.setContext("wv_active_title", activeTitle)
        store.breadcrumb(msg)
        store.writeReport(
            domain: "SmartTube.WrongVideo", code: 2,
            summary: "Wrong video at readyToPlay: intended=\(intendedId) active=\(activeId)")
    }
}

// MARK: - DiagnosticsStore

/// Thread-safe file-backed store behind `DiagnosticsLogger`.
final class DiagnosticsStore: @unchecked Sendable {
    static let shared = DiagnosticsStore()

    static let maxBreadcrumbs = 500
    static let maxReports = 20

    let directory: URL?
    private let lock = NSLock()
    private var breadcrumbs: [String] = []
    private var context: [String: String] = [:]
    private var reportID = ""
    private var sessionHandle: FileHandle?
    private let log = Logger(subsystem: appSubsystem, category: "Diagnostics")

    private init() {
        #if os(tvOS)
        // tvOS only guarantees Caches for app-written files.
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        #else
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        #endif
        directory = base?.appendingPathComponent("Diagnostics", isDirectory: true)
    }

    func startSession(reportID: String) {
        lock.withLock {
            self.reportID = reportID
            guard let directory else { return }
            let fm = FileManager.default
            try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
            let current = directory.appendingPathComponent("session.log")
            let previous = directory.appendingPathComponent("previous-session.log")
            if fm.fileExists(atPath: current.path) {
                try? fm.removeItem(at: previous)
                try? fm.moveItem(at: current, to: previous)
            }
            fm.createFile(atPath: current.path, contents: Data(header(title: "Session").utf8))
            sessionHandle = try? FileHandle(forWritingTo: current)
            _ = try? sessionHandle?.seekToEnd()
        }
        NSSetUncaughtExceptionHandler { exception in
            DiagnosticsStore.shared.recordUncaughtException(exception)
        }
        log.notice("diagnostics session \(reportID, privacy: .public) → \(self.directory?.path ?? "nil", privacy: .public)")
    }

    func breadcrumb(_ line: String) {
        let stamped = "\(Date().formatted(.iso8601)) \(line)"
        lock.withLock {
            breadcrumbs.append(stamped)
            if breadcrumbs.count > Self.maxBreadcrumbs {
                breadcrumbs.removeFirst(breadcrumbs.count - Self.maxBreadcrumbs)
            }
            try? sessionHandle?.write(contentsOf: Data((stamped + "\n").utf8))
        }
    }

    func setContext(_ key: String, _ value: String) {
        lock.withLock { context[key] = value }
    }

    func writeReport(domain: String, code: Int, summary: String, extra: String? = nil) {
        lock.withLock {
            guard let directory else { return }
            var text = header(title: "\(domain) (\(code))")
            text += "Summary: \(summary)\n"
            if let extra { text += "\n\(extra)\n" }
            text += "\n== Context ==\n"
            for key in context.keys.sorted() { text += "\(key) = \(context[key] ?? "")\n" }
            text += "\n== Breadcrumbs (last \(breadcrumbs.count)) ==\n"
            text += breadcrumbs.joined(separator: "\n") + "\n"

            let stamp = Date().formatted(.iso8601).replacingOccurrences(of: ":", with: "")
            let safeDomain = domain.replacingOccurrences(of: "/", with: "_")
            let url = directory.appendingPathComponent("report-\(stamp)-\(safeDomain).txt")
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? Data(text.utf8).write(to: url, options: .atomic)
            pruneReports(in: directory)
        }
    }

    private func recordUncaughtException(_ exception: NSException) {
        let stack = exception.callStackSymbols.joined(separator: "\n")
        writeReport(
            domain: "SmartTube.Crash", code: 0,
            summary: "Uncaught \(exception.name.rawValue): \(exception.reason ?? "no reason")",
            extra: "== Call stack ==\n\(stack)")
    }

    /// Caller holds `lock`.
    private func header(title: String) -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        return """
            SmartTube diagnostics — \(title)
            Time: \(Date().formatted(.iso8601))  Report ID: \(reportID)
            App: \(version) (\(build))  OS: \(os)

            """
    }

    /// Caller holds `lock`.
    private func pruneReports(in directory: URL) {
        let fm = FileManager.default
        let reports = ((try? fm.contentsOfDirectory(atPath: directory.path)) ?? [])
            .filter { $0.hasPrefix("report-") }
            .sorted()
        for name in reports.dropLast(Self.maxReports) {
            try? fm.removeItem(at: directory.appendingPathComponent(name))
        }
    }
}
