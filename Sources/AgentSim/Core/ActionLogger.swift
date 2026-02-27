import Foundation

/// A single auto-logged action entry (JSONL format).
struct ActionLogEntry: Codable {
  let timestamp: String
  let action: String          // "tap", "swipe", "type"
  let target: String          // "@e3", "up", "hello world"
  let refName: String?        // Element name if tapped by ref
  let fingerprint: String?    // Screen fingerprint BEFORE the action
  let screenName: String?     // Screen name BEFORE the action
}

/// Fire-and-forget JSONL logger for all actions.
/// Every `tap`, `swipe`, and `type` auto-appends here — the agent never calls this directly.
enum ActionLogger {

  static var logPath: String {
    let dir = ProjectConfig.journalsDirectory()
    return (dir as NSString).appendingPathComponent("action-log.jsonl")
  }

  /// Append an action entry to the JSONL log. Fails silently — logging should never block actions.
  static func log(_ entry: ActionLogEntry) {
    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      let data = try encoder.encode(entry)
      guard var line = String(data: data, encoding: .utf8) else { return }
      line += "\n"

      let dir = (logPath as NSString).deletingLastPathComponent
      try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

      if FileManager.default.fileExists(atPath: logPath) {
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: logPath))
        handle.seekToEndOfFile()
        handle.write(Data(line.utf8))
        handle.closeFile()
      } else {
        try line.write(toFile: logPath, atomically: true, encoding: .utf8)
      }
    } catch {
      // Silent — logging must never break the action
    }
  }

  /// Build an entry from the current ref store state (no extra AX tree read).
  static func entry(action: String, target: String, refName: String? = nil) -> ActionLogEntry {
    var fingerprint: String?
    var screenName: String?

    if let snapshot = try? RefStore.load() {
      fingerprint = snapshot.fingerprint
      screenName = snapshot.screenName
    }

    return ActionLogEntry(
      timestamp: ISO8601DateFormatter().string(from: Date()),
      action: action,
      target: target,
      refName: refName,
      fingerprint: fingerprint,
      screenName: screenName
    )
  }
}
