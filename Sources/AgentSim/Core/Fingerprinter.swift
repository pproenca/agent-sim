import CommonCrypto
import Foundation

/// Computes a stable fingerprint for a screen based on its accessibility tree.
/// Two screens with the same elements in the same positions produce the same fingerprint.
enum Fingerprinter {

  static func fingerprint(_ tree: AXNode) -> String {
    let lines = tree.flattened()
      .filter { !$0.displayName.isEmpty && $0.frame.width > 0 }
      .map { node in
        let x = Int(node.frame.x)
        let y = Int(node.frame.y)
        let w = Int(node.frame.width)
        let h = Int(node.frame.height)
        return "\(node.role)|\(node.displayName)|\(x)|\(y)|\(w)|\(h)"
      }
      .sorted()

    let joined = lines.joined(separator: "\n")
    return String(sha256(joined).prefix(32)).lowercased()
  }

  /// Short fingerprint for display (first 8 chars of tree fingerprint).
  static func shortFingerprint(_ tree: AXNode) -> String {
    String(fingerprint(tree).prefix(8))
  }

  /// Short fingerprint from a pre-computed full fingerprint string (first 8 chars).
  static func shortFingerprint(from fullFingerprint: String) -> String {
    String(fullFingerprint.prefix(8))
  }

  // MARK: - Private

  private static func sha256(_ string: String) -> String {
    let data = Data(string.utf8)
    var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
    data.withUnsafeBytes { buffer in
      _ = CC_SHA256(buffer.baseAddress, CC_LONG(buffer.count), &hash)
    }
    return hash.map { String(format: "%02x", $0) }.joined()
  }
}
