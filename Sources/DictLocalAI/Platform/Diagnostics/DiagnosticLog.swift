import DictCore
import Foundation
import OSLog

final class DiagnosticLog: @unchecked Sendable {
  static let shared = DiagnosticLog()

  private let lock = NSLock()
  private let handle: FileHandle?
  private(set) var activeLogURL: URL?
  private let system = Logger(subsystem: "app.dictlocalai", category: "diagnostics")
  private let started = ProcessInfo.processInfo.systemUptime
  private var lastMainHeartbeat = ProcessInfo.processInfo.systemUptime
  private var stalled = false
  private var watchdog: DispatchSourceTimer?
  private var dropped = DroppedLogRun()

  private init() {
    let environment = ProcessInfo.processInfo.environment
    let fileManager = FileManager.default
    let libraryDirectory =
      fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first
      ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent(
        "Library", isDirectory: true)
    let base = DiagnosticLogDirectory.resolve(
      libraryDirectory: libraryDirectory,
      overridePath: environment["DICT_LOG_DIR"])
    try? fileManager.createDirectory(
      at: base, withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    let name =
      "session-\(formatter.string(from: Date()))-\(ProcessInfo.processInfo.processIdentifier).log"
    let url = base.appendingPathComponent(name)
    if fileManager.createFile(
      atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
    {
      let opened = try? FileHandle(forWritingTo: url)
      handle = opened
      activeLogURL = opened == nil ? nil : url
    } else {
      handle = nil
      activeLogURL = nil
    }
    if let children = try? FileManager.default.contentsOfDirectory(
      at: base, includingPropertiesForKeys: [.contentModificationDateKey])
    {
      let deadline = Date().addingTimeInterval(-30 * 86_400)
      for url in children
      where url.lastPathComponent.hasPrefix("session-")
        && url.pathExtension == "log"
      {
        if let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey])
          .contentModificationDate, modified < deadline
        {
          try? FileManager.default.removeItem(at: url)
        }
      }
    }
  }

  func event(_ area: String, _ name: String, _ values: String = "") {
    let line = format(area, name, values)
    lock.lock()
    if let handle {
      // Use the throwing writer so disk-full errors are handled without an Objective-C exception.
      do {
        if dropped.pending > 0 {
          try handle.write(
            contentsOf: Data(
              format("diagnostics", "lines_dropped", "count=\(dropped.pending)").utf8))
          dropped.clear()
        }
        try handle.write(contentsOf: Data(line.utf8))
      } catch {
        if dropped.failed() { reportFirstDroppedWrite(error) }
      }
    }
    lock.unlock()
    if area == "usage" {
      system.info("\(line, privacy: .public)")
    } else {
      system.debug("\(line, privacy: .private)")
    }
  }

  private func format(_ area: String, _ name: String, _ values: String) -> String {
    let elapsed = String(format: "%.3f", ProcessInfo.processInfo.systemUptime - started)
    return "[+\(elapsed)s] [\(area)] \(name) \(DiagnosticSanitizer.scrub(values))\n"
  }

  // Send the write failure to the system log when the file cannot accept the entry.
  private func reportFirstDroppedWrite(_ error: Error) {
    let ns = error as NSError
    system.error(
      "session log write failed domain=\(ns.domain, privacy: .public) code=\(ns.code, privacy: .public)"
    )
  }

  func mainHeartbeat() {
    lock.lock()
    lastMainHeartbeat = ProcessInfo.processInfo.systemUptime
    stalled = false
    lock.unlock()
  }

  func startWatchdog() {
    lock.lock()
    if watchdog != nil {
      lock.unlock()
      return
    }
    let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
    watchdog = timer
    lock.unlock()
    timer.schedule(deadline: .now() + 5, repeating: 5)
    timer.setEventHandler { [weak self] in
      guard let self else { return }
      self.lock.lock()
      let lag = ProcessInfo.processInfo.systemUptime - self.lastMainHeartbeat
      let shouldReport = lag > 10 && !self.stalled
      if shouldReport { self.stalled = true }
      self.lock.unlock()
      if shouldReport { self.event("watchdog", "main_thread_stall", "seconds=\(Int(lag))") }
    }
    timer.resume()
  }
}

/// Track dropped lines until the next successful write can report them.
struct DroppedLogRun {
  private(set) var pending = 0

  /// Counts a lost line. True for the first loss of a run, which is the one to report.
  mutating func failed() -> Bool {
    pending += 1
    return pending == 1
  }

  mutating func clear() { pending = 0 }
}
