import CommonCrypto
import Foundation

/// SHA-256 utilities for file content checksumming.
enum FileChecksum {

  /// Compute SHA-256 hex digest of raw bytes.
  static func sha256(_ data: Data) -> String {
    var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
    data.withUnsafeBytes { buffer in
      _ = CC_SHA256(buffer.baseAddress, CC_LONG(buffer.count), &hash)
    }
    return hash.map { String(format: "%02x", $0) }.joined()
  }

  /// Read a file and return its SHA-256 hex digest. Returns nil if the file can't be read.
  static func sha256(atPath path: String) -> String? {
    guard let data = FileManager.default.contents(atPath: path) else { return nil }
    return sha256(data)
  }
}
