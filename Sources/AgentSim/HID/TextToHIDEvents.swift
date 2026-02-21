// Inlined from AXe (cameroncooke/AXe) — MIT License
import FBControlCore
import FBSimulatorControl
import Foundation

enum TextToHIDEvents {

  enum TextConversionError: Error, LocalizedError {
    case unsupportedCharacter(Character)

    var errorDescription: String? {
      switch self {
      case .unsupportedCharacter(let char):
        return "No keycode found for character: '\(char)'"
      }
    }
  }

  private static func simpleKeyEvent(keyCode: Int) -> [FBSimulatorHIDEvent] {
    [.keyDown(UInt32(keyCode)), .keyUp(UInt32(keyCode))]
  }

  private static func shiftedKeyEvent(keyCode: Int) -> [FBSimulatorHIDEvent] {
    [.keyDown(225), .keyDown(UInt32(keyCode)), .keyUp(UInt32(keyCode)), .keyUp(225)]
  }

  private static func eventsForCharacter(_ character: Character) throws -> [FBSimulatorHIDEvent] {
    let keyEvent = KeyEvent.keyCodeForString(String(character))
    guard keyEvent.keyCode != 0 else {
      throw TextConversionError.unsupportedCharacter(character)
    }
    return keyEvent.shift ? shiftedKeyEvent(keyCode: keyEvent.keyCode) : simpleKeyEvent(keyCode: keyEvent.keyCode)
  }

  static func convertTextToHIDEvents(_ text: String) throws -> [FBSimulatorHIDEvent] {
    try text.flatMap { try eventsForCharacter($0) }
  }
}
