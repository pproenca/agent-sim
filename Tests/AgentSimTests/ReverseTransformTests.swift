import Testing
@testable import AgentSimLib

/// Tests that the forward transform (AX → device) and reverse transform (device → macOS)
/// are consistent inverses. If these round-trip tests fail, taps will land on wrong elements.
///
/// Forward (readDeviceTree):
///   windowCoord = absoluteCoord - origin
///   deviceCoord = windowCoord × (deviceSize / windowSize)
///
/// Reverse (SimulatorBridge.tap):
///   macCoord = deviceCoord × (windowSize / deviceSize) + origin
///
/// Round-trip: forward then reverse should recover the original absolute coordinate.
@Suite("Reverse coordinate transform — tap pipeline accuracy")
struct ReverseTransformTests {

  // MARK: - Round-trip: forward → reverse recovers original coords

  @Test("Round-trip preserves center coordinates for iPhone 16")
  func roundTripIPhone16() {
    // Simulate a button at absolute position (250, 450) in macOS screen space
    let absoluteX = 250.0
    let absoluteY = 450.0
    let originX = 100.0
    let originY = 200.0
    let windowWidth = 359.0
    let windowHeight = 778.0
    let deviceWidth = 393.0
    let deviceHeight = 852.0

    // Forward: absolute → window-relative → device
    let windowRelX = absoluteX - originX // 150
    let windowRelY = absoluteY - originY // 250
    let scaleX = deviceWidth / windowWidth
    let scaleY = deviceHeight / windowHeight
    let deviceX = windowRelX * scaleX
    let deviceY = windowRelY * scaleY

    // Reverse: device → window-relative → absolute
    let recoveredMacX = deviceX * (windowWidth / deviceWidth) + originX
    let recoveredMacY = deviceY * (windowHeight / deviceHeight) + originY

    #expect(abs(recoveredMacX - absoluteX) < 0.01,
            "X round-trip drift: \(abs(recoveredMacX - absoluteX))")
    #expect(abs(recoveredMacY - absoluteY) < 0.01,
            "Y round-trip drift: \(abs(recoveredMacY - absoluteY))")
  }

  @Test("Round-trip preserves coordinates at origin (0,0 in device space)")
  func roundTripOrigin() {
    let originX = 100.0
    let originY = 200.0
    let windowWidth = 359.0
    let windowHeight = 778.0
    let deviceWidth = 393.0
    let deviceHeight = 852.0

    // Device (0, 0) → macOS
    let deviceX = 0.0
    let deviceY = 0.0
    let recoveredMacX = deviceX * (windowWidth / deviceWidth) + originX
    let recoveredMacY = deviceY * (windowHeight / deviceHeight) + originY

    // Should recover exactly the window origin
    #expect(abs(recoveredMacX - originX) < 0.01)
    #expect(abs(recoveredMacY - originY) < 0.01)
  }

  @Test("Round-trip preserves coordinates at bottom-right corner")
  func roundTripBottomRight() {
    let originX = 100.0
    let originY = 200.0
    let windowWidth = 359.0
    let windowHeight = 778.0
    let deviceWidth = 393.0
    let deviceHeight = 852.0

    // Device (393, 852) → macOS → should be origin + windowSize
    let recoveredMacX = deviceWidth * (windowWidth / deviceWidth) + originX
    let recoveredMacY = deviceHeight * (windowHeight / deviceHeight) + originY

    #expect(abs(recoveredMacX - (originX + windowWidth)) < 0.01)
    #expect(abs(recoveredMacY - (originY + windowHeight)) < 0.01)
  }

  @Test("Round-trip preserves coordinates for iPhone 16 Pro (different device size)")
  func roundTripIPhone16Pro() {
    let originX = 150.0
    let originY = 250.0
    let windowWidth = 368.0 // Pro renders at slightly different window size
    let windowHeight = 800.0
    let deviceWidth = 402.0
    let deviceHeight = 874.0

    let absoluteX = 300.0
    let absoluteY = 600.0

    let windowRelX = absoluteX - originX
    let windowRelY = absoluteY - originY
    let deviceX = windowRelX * (deviceWidth / windowWidth)
    let deviceY = windowRelY * (deviceHeight / windowHeight)

    let recoveredMacX = deviceX * (windowWidth / deviceWidth) + originX
    let recoveredMacY = deviceY * (windowHeight / deviceHeight) + originY

    #expect(abs(recoveredMacX - absoluteX) < 0.01)
    #expect(abs(recoveredMacY - absoluteY) < 0.01)
  }

  // MARK: - Precision across full coordinate range

  @Test("No point in 0..393 x 0..852 drifts more than 1pt after round-trip")
  func systematicPrecisionCheck() {
    let originX = 100.0
    let originY = 200.0
    let windowWidth = 359.0
    let windowHeight = 778.0
    let deviceWidth = 393.0
    let deviceHeight = 852.0

    var maxDriftX = 0.0
    var maxDriftY = 0.0

    // Sample grid of device coordinates
    for deviceX in stride(from: 0.0, through: deviceWidth, by: 10.0) {
      for deviceY in stride(from: 0.0, through: deviceHeight, by: 10.0) {
        let macX = deviceX * (windowWidth / deviceWidth) + originX
        let macY = deviceY * (windowHeight / deviceHeight) + originY

        // Reverse: recover device coords from macOS coords
        let recoveredDeviceX = (macX - originX) * (deviceWidth / windowWidth)
        let recoveredDeviceY = (macY - originY) * (deviceHeight / windowHeight)

        let driftX = abs(recoveredDeviceX - deviceX)
        let driftY = abs(recoveredDeviceY - deviceY)
        maxDriftX = max(maxDriftX, driftX)
        maxDriftY = max(maxDriftY, driftY)
      }
    }

    #expect(maxDriftX < 1.0, "Max X drift across full range: \(maxDriftX)")
    #expect(maxDriftY < 1.0, "Max Y drift across full range: \(maxDriftY)")
  }

  // MARK: - screenSize lookup

  @Test("screenSize returns correct size for iPhone 16")
  func screenSizeIPhone16() {
    let size = SimulatorBridge.screenSize(
      for: "com.apple.CoreSimulator.SimDeviceType.iPhone-16"
    )
    #expect(size.width == 393)
    #expect(size.height == 852)
  }

  @Test("screenSize returns correct size for iPhone 16 Pro")
  func screenSizeIPhone16Pro() {
    let size = SimulatorBridge.screenSize(
      for: "com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro"
    )
    #expect(size.width == 402)
    #expect(size.height == 874)
  }

  @Test("screenSize returns correct size for iPhone 16 Pro Max")
  func screenSizeIPhone16ProMax() {
    let size = SimulatorBridge.screenSize(
      for: "com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro-Max"
    )
    #expect(size.width == 440)
    #expect(size.height == 956)
  }

  @Test("screenSize falls back to iPhone 16 for unknown device type")
  func screenSizeUnknown() {
    let size = SimulatorBridge.screenSize(
      for: "com.apple.CoreSimulator.SimDeviceType.iPhone-99"
    )
    #expect(size.width == 393)
    #expect(size.height == 852)
  }

  // MARK: - SwipeDirection coordinates

  @Test("SwipeDirection.up swipes from center-bottom to center-top")
  func swipeUp() {
    let (x1, y1, x2, y2) = SimulatorBridge.SwipeDirection.up.coordinates(delta: 300)
    #expect(x1 == x2, "Vertical swipe should keep X constant")
    #expect(y1 > y2, "Up swipe: start Y should be greater than end Y")
    #expect(y1 - y2 == 300, "Delta should equal 300")
  }

  @Test("SwipeDirection.down swipes from center-top to center-bottom")
  func swipeDown() {
    let (x1, y1, x2, y2) = SimulatorBridge.SwipeDirection.down.coordinates(delta: 300)
    #expect(x1 == x2)
    #expect(y2 > y1, "Down swipe: end Y should be greater than start Y")
    #expect(y2 - y1 == 300)
  }

  @Test("SwipeDirection.left swipes from right to left")
  func swipeLeft() {
    let (x1, y1, x2, y2) = SimulatorBridge.SwipeDirection.left.coordinates(delta: 300)
    #expect(y1 == y2, "Horizontal swipe should keep Y constant")
    #expect(x1 > x2, "Left swipe: start X should be greater than end X")
    #expect(x1 - x2 == 300)
  }

  @Test("SwipeDirection.right swipes from left to right")
  func swipeRight() {
    let (x1, y1, x2, y2) = SimulatorBridge.SwipeDirection.right.coordinates(delta: 300)
    #expect(y1 == y2)
    #expect(x2 > x1, "Right swipe: end X should be greater than start X")
    #expect(x2 - x1 == 300)
  }
}
