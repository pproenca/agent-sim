import ArgumentParser
import Foundation

struct Network: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Show recent HTTP network activity from CFNetwork diagnostics."
  )

  @Option(name: .long, help: "Bundle identifier of the app (for relaunch hints).")
  var bundleID: String = "com.maddie.appnative"

  @Option(name: .long, help: "Process name to search in logs (default: MaddieAppNative).")
  var processName: String = "MaddieAppNative"

  @Flag(name: .long, help: "Only show errors (status >= 400 or connection failures).")
  var errors = false

  @Option(name: .long, help: "Time window in seconds (default: 30).")
  var last: Int = 30

  @Flag(name: .long, help: "Human-readable output instead of JSON.")
  var pretty = false

  func run() async throws {
    let device = try await SimulatorBridge.resolveDevice()
    let simID = device.udid

    let raw: String
    let queryFailed: Bool
    do {
      raw = try await SimulatorBridge.queryLogs(
        simulatorID: simID, processName: processName, subsystem: "com.apple.CFNetwork", lastSeconds: last
      )
      queryFailed = false
    } catch {
      raw = ""
      queryFailed = true
    }

    let result = NetworkLogParser.parse(raw)

    var requests = result.requests

    if errors {
      requests = requests.filter { $0.isError }
    }

    if pretty {
      printPretty(requests, result: result, queryFailed: queryFailed)
    } else {
      printJSON(requests, result: result, queryFailed: queryFailed)
    }
  }

  // MARK: - Pretty Output

  private func printPretty(
    _ requests: [NetworkLogParser.NetworkRequest],
    result: NetworkLogParser.ParseResult,
    queryFailed: Bool
  ) {
    if queryFailed {
      print("Log query failed. Verify the simulator is running.")
      print("Relaunch with: agent-sim launch --network \(bundleID)")
      return
    }

    guard result.diagnosticsEnabled else {
      printNoDiagnosticsHint(rawCount: result.rawEntries.count)
      return
    }

    let errorCount = requests.filter(\.isError).count
    let label = errors ? "errors" : "requests"
    print("Network (last \(last)s) — \(requests.count) \(label)\(errorCount > 0 ? ", \(errorCount) error\(errorCount == 1 ? "" : "s")" : "")")
    print("")

    if requests.isEmpty {
      print("  No \(errors ? "errors" : "requests") found.")
    } else {
      for req in requests {
        let status = req.statusCode.map { "\($0)" } ?? "---"
        let duration = req.durationMs.map { "(\($0)ms)" } ?? ""
        let errorTag = req.isError ? "  ERROR" : ""
        let method = req.method ?? "???"
        let url = req.url.map { shortenURL($0) } ?? ""
        print("  #\(req.index)  \(req.timestamp)  \(method.padding(toLength: 6, withPad: " ", startingAt: 0))\(url)  \(status)  \(duration)\(errorTag)")
      }
    }

    let errorRequests = requests.filter(\.isError)
    if !errorRequests.isEmpty && !errors {
      print("")
      print("Errors:")
      for req in errorRequests {
        let status = req.statusCode.map { "\($0)" } ?? "failed"
        let detail = req.errorDetail ?? ""
        let method = req.method ?? "???"
        let url = req.url.map { shortenURL($0) } ?? "unknown"
        print("  #\(req.index) \(method) \(url) → \(status)\(detail.isEmpty ? "" : " (\(detail))")")
      }
    }

    print("")
    if !errors && errorCount > 0 {
      print("Hint: agent-sim network --errors --pretty    Show only errors")
    }
  }

  private func printNoDiagnosticsHint(rawCount: Int) {
    if rawCount > 0 {
      print("No CFNetwork diagnostic logs found (\(rawCount) raw log entries available in JSON mode).")
    } else {
      print("No network diagnostics found.")
    }
    print("Relaunch with: agent-sim launch --network \(bundleID)")
  }

  // MARK: - JSON Output

  private func printJSON(
    _ requests: [NetworkLogParser.NetworkRequest],
    result: NetworkLogParser.ParseResult,
    queryFailed: Bool
  ) {
    let output = NetworkJSONOutput(
      diagnosticsEnabled: result.diagnosticsEnabled,
      queryFailed: queryFailed,
      timeWindowSeconds: last,
      errorsOnly: errors,
      bundleID: bundleID,
      requests: requests,
      rawEntries: result.diagnosticsEnabled ? [] : result.rawEntries
    )

    JSONOutput.print(output)
  }

  // MARK: - Helpers

  private func shortenURL(_ urlString: String) -> String {
    guard let url = URL(string: urlString) else { return urlString }
    let path = url.path
    if let query = url.query, !query.isEmpty {
      return "\(path)?\(query)"
    }
    return path.isEmpty ? urlString : path
  }
}

// MARK: - JSON Model

private struct NetworkJSONOutput: Encodable {
  let diagnosticsEnabled: Bool
  let queryFailed: Bool
  let timeWindowSeconds: Int
  let errorsOnly: Bool
  let bundleID: String
  let requests: [NetworkLogParser.NetworkRequest]
  let rawEntries: [NetworkLogParser.RawLogEntry]
}
