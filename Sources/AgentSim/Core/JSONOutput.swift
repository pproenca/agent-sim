import Foundation

/// Shared JSON encoding helper for command output.
/// Centralizes the encoder configuration and error reporting.
enum JSONOutput {
  private static let encoder: JSONEncoder = {
    let e = JSONEncoder()
    e.outputFormatting = [.prettyPrinted, .sortedKeys]
    return e
  }()

  /// Encode a value to pretty-printed JSON and print to stdout.
  /// Logs encoding errors to stderr instead of silently swallowing them.
  static func print(_ value: some Encodable) {
    do {
      let data = try encoder.encode(value)
      Swift.print(String(data: data, encoding: .utf8) ?? "{}")
    } catch {
      FileHandle.standardError.write(Data("JSON encoding error: \(error)\n".utf8))
    }
  }
}
