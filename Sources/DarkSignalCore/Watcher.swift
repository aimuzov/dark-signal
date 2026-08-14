import AppKit
import Foundation

/// Calls back on every light/dark switch, and once at start-up.
///
/// The start-up call is what makes the tool usable from a LaunchAgent: the appearance
/// may well have changed while nothing was watching (another user session, a schedule,
/// a reboot in the evening), and a client that only ever hears about *changes* would
/// stay on last week's theme until the next one.
public final class Watcher {
    public static let notificationName = Notification.Name("AppleInterfaceThemeChangedNotification")

    private let onChange: (Appearance) -> Void

    public init(onChange: @escaping (Appearance) -> Void) {
        self.onChange = onChange
    }

    public func start() {
        onChange(AppearanceReader.current())

        DistributedNotificationCenter.default.addObserver(
            forName: Self.notificationName,
            object: nil,
            queue: nil
        ) { [onChange] _ in
            onChange(AppearanceReader.current())
        }
    }

    /// Runs the notification loop. Never returns.
    public func run() -> Never {
        start()
        // A DistributedNotificationCenter observer needs a running loop to be called;
        // NSApplication provides one without the app ever showing a window.
        NSApplication.shared.run()
        // NSApplication.run() does not return, but the compiler wants an exit
        exit(0)
    }
}

public enum Executor {
    /// Runs a command with `$DARKMODE` set to 1 or 0, the convention the tools in this
    /// niche already use, plus `$DARK_SIGNAL_APPEARANCE` spelled out for readability.
    @discardableResult
    public static func run(_ command: [String], appearance: Appearance) -> Int32 {
        guard let executable = command.first else {
            return 1
        }

        var environment = ProcessInfo.processInfo.environment
        environment["DARKMODE"] = appearance.environmentValue
        environment["DARK_SIGNAL_APPEARANCE"] = appearance.rawValue

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + command.dropFirst()
        process.environment = environment

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            FileHandle.standardError.write(Data("dark-signal: could not run \(executable): \(error)\n".utf8))
            return 1
        }
    }
}
