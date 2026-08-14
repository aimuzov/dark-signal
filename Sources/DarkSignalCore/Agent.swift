import Foundation

/// The LaunchAgent that keeps dark-signal running across logins.
///
/// Every neighbour in this niche asks the user to write this plist by hand, which is
/// where most of the setup goes wrong: a stale path after an upgrade, a label that
/// does not match the file name, a forgotten `launchctl load`. `install` generates it
/// from the binary that is actually running and loads it.
public enum Agent {
    public static let label = "com.github.aimuzov.dark-signal"

    public static func plistURL(home: URL) -> URL {
        home
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(label).plist", isDirectory: false)
    }

    public static func plist(binary: String, arguments: [String]) -> [String: Any] {
        [
            "Label": label,
            "ProgramArguments": [binary] + arguments,
            // The watcher is meant to be running whenever the user is logged in
            "RunAtLoad": true,
            "KeepAlive": true,
            "ProcessType": "Background",
        ]
    }

    public static func plistData(binary: String, arguments: [String]) throws -> Data {
        try PropertyListSerialization.data(
            fromPropertyList: plist(binary: binary, arguments: arguments),
            format: .xml,
            options: 0
        )
    }
}
