import Testing
@testable import AgentSimLib

@Suite("Fingerprinter — screen identity hashing")
struct FingerprinterTests {

  @Test("Same tree produces the same fingerprint (deterministic)")
  func deterministic() {
    let tree = AXNodeBuilder.node(
      role: "AXGroup",
      children: [
        AXNodeBuilder.button("OK", at: (196, 400)),
        AXNodeBuilder.text("Title", at: (0, 100)),
      ]
    )

    let fp1 = Fingerprinter.fingerprint(tree)
    let fp2 = Fingerprinter.fingerprint(tree)

    #expect(fp1 == fp2)
    #expect(!fp1.isEmpty)
  }

  @Test("Different element positions produce different fingerprints")
  func positionSensitive() {
    let tree1 = AXNodeBuilder.node(
      role: "AXGroup",
      children: [AXNodeBuilder.button("OK", at: (100, 200))]
    )
    let tree2 = AXNodeBuilder.node(
      role: "AXGroup",
      children: [AXNodeBuilder.button("OK", at: (300, 500))]
    )

    #expect(Fingerprinter.fingerprint(tree1) != Fingerprinter.fingerprint(tree2))
  }

  @Test("Elements whose displayName falls back to role still contribute to fingerprint")
  func roleFallbackContributes() {
    // AXImage with no label/identifier/value — displayName falls back to "AXImage"
    // This SHOULD affect the fingerprint because position+role is meaningful
    let withImage = AXNodeBuilder.node(
      role: "AXGroup",
      children: [
        AXNodeBuilder.button("OK", at: (196, 400)),
        AXNodeBuilder.node(role: "AXImage", x: 50, y: 50, width: 100, height: 100),
      ]
    )
    let withoutImage = AXNodeBuilder.node(
      role: "AXGroup",
      children: [
        AXNodeBuilder.button("OK", at: (196, 400)),
      ]
    )

    // Different trees should produce different fingerprints
    #expect(Fingerprinter.fingerprint(withImage) != Fingerprinter.fingerprint(withoutImage))
  }

  @Test("Elements with zero width are excluded from fingerprint")
  func excludesZeroWidth() {
    let withZero = AXNodeBuilder.node(
      role: "AXGroup",
      children: [
        AXNodeBuilder.button("OK", at: (196, 400)),
        AXNodeBuilder.node(role: "AXButton", label: "Hidden", x: 0, y: 0, width: 0, height: 44),
      ]
    )
    let withoutZero = AXNodeBuilder.node(
      role: "AXGroup",
      children: [
        AXNodeBuilder.button("OK", at: (196, 400)),
      ]
    )

    #expect(Fingerprinter.fingerprint(withZero) == Fingerprinter.fingerprint(withoutZero))
  }

  @Test("shortFingerprint returns first 8 characters")
  func shortFingerprint() {
    let tree = AXNodeBuilder.node(
      role: "AXGroup",
      children: [AXNodeBuilder.button("OK", at: (196, 400))]
    )

    let full = Fingerprinter.fingerprint(tree)
    let short = Fingerprinter.shortFingerprint(tree)

    #expect(short.count == 8)
    #expect(full.hasPrefix(short))
  }

  @Test("Fingerprint has expected length (32 hex chars)")
  func fingerprintLength() {
    let tree = AXNodeBuilder.button("Test", at: (100, 200))
    let fp = Fingerprinter.fingerprint(tree)

    #expect(fp.count == 32)
    #expect(fp.allSatisfy { $0.isHexDigit })
  }

  @Test("shortFingerprint(from:) returns first 8 chars of a full fingerprint string")
  func shortFingerprintFromString() {
    let full = "abcdef1234567890abcdef1234567890"
    let short = Fingerprinter.shortFingerprint(from: full)
    #expect(short == "abcdef12")
  }
}
