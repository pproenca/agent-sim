/// Named constants for device dimensions and layout thresholds.
/// Centralizes magic numbers used across SimulatorBridge, ScreenAnalysis, and SwipeDirection.
enum DeviceConstants {
  /// Default screen width in points (iPhone 16).
  static let defaultWidth = 393
  /// Default screen height in points (iPhone 16).
  static let defaultHeight = 852
  /// Maximum Y coordinate for the navigation bar area.
  static let navigationBarMaxY: Double = 100
  /// Minimum screen height to suggest scrollable content.
  static let scrollableContentThreshold: Double = 900
}
