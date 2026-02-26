import Testing
@testable import AgentSimLib

@Suite("AXTreeReader — coordinate normalization")
struct AXCoordinateNormalizationTests {

  @Test("No-op when tree is already in device-point coordinates")
  func noOpForDeviceSpaceTree() {
    let button = AXNodeBuilder.button("Sign In", at: (196, 426))
    let tree = AXNodeBuilder.simulatorTree(
      windowOrigin: (0, 0),
      windowSize: (393, 852),
      screenChildren: [button]
    )

    let normalized = AXTreeReader.normalizeToDevicePoints(
      tree,
      deviceWidth: 393,
      deviceHeight: 852
    )

    let interactive = AXTreeReader.collectInteractive(normalized)
    #expect(interactive.count == 1)
    #expect(abs(interactive[0].frame.centerX - 196) < 0.5)
    #expect(abs(interactive[0].frame.centerY - 426) < 0.5)
  }

  @Test("Normalizes simulator-window coordinates to device points")
  func normalizesWindowSpaceTree() {
    let button = AXNodeBuilder.button("Sign In", at: (250, 450))
    let tree = AXNodeBuilder.simulatorTree(
      windowOrigin: (100, 200),
      windowSize: (359, 778),
      screenChildren: [button]
    )

    let normalized = AXTreeReader.normalizeToDevicePoints(
      tree,
      deviceWidth: 393,
      deviceHeight: 852
    )

    let interactive = AXTreeReader.collectInteractive(normalized)
    #expect(interactive.count == 1)

    // Expected: (raw - origin) scaled by device/window ratio
    #expect(abs(interactive[0].frame.centerX - 164.21) < 1.0)
    #expect(abs(interactive[0].frame.centerY - 273.78) < 1.0)
  }

  @Test("Applies origin offset even when scale is 1:1")
  func normalizesOriginOnlyTree() {
    let button = AXNodeBuilder.button("Continue", at: (200, 300))
    let tree = AXNodeBuilder.simulatorTree(
      windowOrigin: (40, 70),
      windowSize: (393, 852),
      screenChildren: [button]
    )

    let normalized = AXTreeReader.normalizeToDevicePoints(
      tree,
      deviceWidth: 393,
      deviceHeight: 852
    )

    let interactive = AXTreeReader.collectInteractive(normalized)
    #expect(interactive.count == 1)
    #expect(abs(interactive[0].frame.centerX - 160) < 0.5)
    #expect(abs(interactive[0].frame.centerY - 230) < 0.5)
  }

  @Test("Viewport inference prefers shallow window frames over deep content frames")
  func viewportInferencePrefersWindow() {
    let deepScroll = AXNodeBuilder.node(
      role: "AXScrollArea",
      x: 0, y: 0, width: 393, height: 2000,
      depth: 4,
      children: [AXNodeBuilder.button("Bottom CTA", at: (196, 1800), depth: 5)]
    )
    let tree = AXNodeBuilder.simulatorTree(
      windowOrigin: (0, 0),
      windowSize: (393, 852),
      screenChildren: [deepScroll]
    )

    let viewport = AXTreeReader.inferredViewportFrame(from: tree)
    #expect(viewport != nil)
    #expect(abs((viewport?.width ?? 0) - 393) < 0.5)
    #expect(abs((viewport?.height ?? 0) - 852) < 0.5)
  }
}
