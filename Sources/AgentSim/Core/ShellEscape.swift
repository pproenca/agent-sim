/// Shell-escapes a string by wrapping in single quotes and escaping embedded quotes.
/// Use this when interpolating user-controlled strings into CLI commands.
func shellEscape(_ string: String) -> String {
  "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'"
}
