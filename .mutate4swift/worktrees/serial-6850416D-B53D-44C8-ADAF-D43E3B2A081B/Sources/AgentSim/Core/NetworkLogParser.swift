import Foundation

enum NetworkLogParser {

  // MARK: - Public Types

  struct NetworkRequest: Encodable {
    let index: Int
    let timestamp: String
    let method: String?
    let url: String?
    let statusCode: Int?
    let isError: Bool
    let errorDetail: String?
    let durationMs: Int?
  }

  struct ParseResult: Encodable {
    let diagnosticsEnabled: Bool
    let requests: [NetworkRequest]
    let rawEntries: [RawLogEntry]
  }

  struct RawLogEntry: Encodable {
    let timestamp: String
    let message: String
  }

  // MARK: - Parsing

  static func parse(_ ndjsonOutput: String) -> ParseResult {
    let lines = ndjsonOutput.components(separatedBy: .newlines).filter { !$0.isEmpty }
    var logEntries: [LogEntry] = []

    for line in lines {
      guard let data = line.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
      else { continue }

      let timestamp = json["timestamp"] as? String ?? ""
      let message = json["eventMessage"] as? String ?? ""
      let subsystem = json["subsystem"] as? String ?? ""

      guard !message.isEmpty else { continue }
      logEntries.append(LogEntry(timestamp: timestamp, message: message, subsystem: subsystem))
    }

    let cfnetworkEntries = logEntries.filter { isCFNetworkEntry($0) }

    if cfnetworkEntries.isEmpty {
      let rawEntries = logEntries.map { RawLogEntry(timestamp: formatTimestamp($0.timestamp), message: $0.message) }
      return ParseResult(diagnosticsEnabled: false, requests: [], rawEntries: rawEntries)
    }

    let requests = correlateRequests(cfnetworkEntries)
    return ParseResult(diagnosticsEnabled: true, requests: requests, rawEntries: [])
  }

  // MARK: - Private

  private struct LogEntry {
    let timestamp: String
    let message: String
    let subsystem: String
  }

  private struct TaskState {
    var statusCode: Int?
    var isError: Bool = false
    var errorDetail: String?
    var method: String?
    var url: String?
    var durationMs: Int?
    var firstTimestamp: String = ""
    var lastTimestamp: String = ""
  }

  /// Matches CFNetwork log entries. These have UUID-format task IDs: `Task <UUID>.<N>`
  /// and come from the `com.apple.CFNetwork` subsystem.
  private static func isCFNetworkEntry(_ entry: LogEntry) -> Bool {
    entry.subsystem == "com.apple.CFNetwork" && taskIDPattern.firstMatch(
      in: entry.message, range: NSRange(entry.message.startIndex..., in: entry.message)
    ) != nil
  }

  // Task <D2686A70-AD68-4B9E-9500-A74972B1EB1F>.<1>
  private static let taskIDPattern = try! NSRegularExpression(
    pattern: #"Task <([A-F0-9-]+)>\.(<?\d+>?)"#, options: .caseInsensitive
  )

  // "received response, status 200"
  private static let responseStatusPattern = try! NSRegularExpression(
    pattern: #"received response, status (\d+)"#
  )

  // "summary for task success {transaction_duration_ms=149, response_status=200, ...}"
  private static let summaryDurationPattern = try! NSRegularExpression(
    pattern: #"transaction_duration_ms=(\d+)"#
  )
  private static let summaryStatusPattern = try! NSRegularExpression(
    pattern: #"response_status=(\d+)"#
  )

  // "finished with error [-999] Error Domain=NSURLErrorDomain Code=-999"
  private static let errorCodePattern = try! NSRegularExpression(
    pattern: #"finished with error \[(-?\d+)\]"#
  )

  // HTTP method + URL (from CFNETWORK_DIAGNOSTICS verbose output, if present)
  private static let requestPattern = try! NSRegularExpression(
    pattern: #"(GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS)\s+(https?://\S+)"#
  )

  private static func correlateRequests(_ entries: [LogEntry]) -> [NetworkRequest] {
    var taskStates: [String: TaskState] = [:]
    var taskOrder: [String] = []

    for entry in entries {
      guard let taskID = extractMatch(taskIDPattern, in: entry.message, group: 1) else { continue }

      if taskStates[taskID] == nil {
        taskStates[taskID] = TaskState(firstTimestamp: entry.timestamp)
        taskOrder.append(taskID)
      }

      taskStates[taskID]?.lastTimestamp = entry.timestamp

      // "received response, status 200"
      if let status = extractMatch(responseStatusPattern, in: entry.message, group: 1),
         let code = Int(status)
      {
        taskStates[taskID]?.statusCode = code
        if code >= 400 {
          taskStates[taskID]?.isError = true
        }
      }

      // Summary line: transaction_duration_ms, response_status
      if entry.message.contains("summary for") {
        if let durationStr = extractMatch(summaryDurationPattern, in: entry.message, group: 1),
           let duration = Int(durationStr)
        {
          taskStates[taskID]?.durationMs = duration
        }
        if taskStates[taskID]?.statusCode == nil,
           let status = extractMatch(summaryStatusPattern, in: entry.message, group: 1),
           let code = Int(status)
        {
          taskStates[taskID]?.statusCode = code
          if code >= 400 {
            taskStates[taskID]?.isError = true
          }
        }
      }

      // "finished with error [-999]"
      if let errorCode = extractMatch(errorCodePattern, in: entry.message, group: 1) {
        taskStates[taskID]?.isError = true
        taskStates[taskID]?.errorDetail = "NSURLError \(errorCode)"
      }

      // HTTP method + URL (if CFNETWORK_DIAGNOSTICS provides them)
      if let method = extractMatch(requestPattern, in: entry.message, group: 1),
         let url = extractMatch(requestPattern, in: entry.message, group: 2)
      {
        taskStates[taskID]?.method = method
        taskStates[taskID]?.url = url
      }
    }

    return taskOrder.enumerated().compactMap { index, taskID -> NetworkRequest? in
      guard let state = taskStates[taskID] else { return nil }

      // Skip tasks with no meaningful data (e.g., only "resuming" seen)
      guard state.statusCode != nil || state.isError else { return nil }

      return NetworkRequest(
        index: index + 1,
        timestamp: formatTimestamp(state.firstTimestamp),
        method: state.method,
        url: state.url,
        statusCode: state.statusCode,
        isError: state.isError,
        errorDetail: state.errorDetail,
        durationMs: state.durationMs
      )
    }
  }

  private static func extractMatch(
    _ regex: NSRegularExpression, in string: String, group: Int
  ) -> String? {
    let range = NSRange(string.startIndex..., in: string)
    guard let match = regex.firstMatch(in: string, range: range),
          group < match.numberOfRanges,
          let groupRange = Range(match.range(at: group), in: string)
    else { return nil }
    return String(string[groupRange])
  }

  /// Extracts HH:mm:ss from `log show` ndjson timestamps.
  /// Format: "2026-02-21 13:33:43.175745+0000" → "13:33:43"
  private static func formatTimestamp(_ raw: String) -> String {
    guard let spaceIndex = raw.firstIndex(of: " "),
          raw.distance(from: spaceIndex, to: raw.endIndex) > 8
    else { return raw }
    let start = raw.index(after: spaceIndex)
    let end = raw.index(start, offsetBy: 8)
    return String(raw[start..<end])
  }
}
