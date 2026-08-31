import os

/// Diagnostics channel. Read with:
///   log show --last 5m --predicate 'subsystem == "dev.anton.2cmd"' --info --debug
enum Log {
    static let permissions = Logger(subsystem: "dev.anton.2cmd", category: "permissions")
    static let tap = Logger(subsystem: "dev.anton.2cmd", category: "tap")
}
