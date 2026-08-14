import Foundation

public enum Command: Equatable {
    /// Send a signal to every process with this name, on every appearance change.
    case signal(process: String, signal: Int32)
    /// Run a command with `$DARKMODE` set, on every appearance change.
    case exec(command: [String])
    /// Write and load a LaunchAgent that runs `dark-signal` with these arguments.
    case install(arguments: [String])
    case uninstall
    /// Print the current appearance and exit.
    case status
    case help
}

public enum OptionsError: Error, Equatable, CustomStringConvertible {
    case unknownCommand(String)
    case missingValue(String)
    case missingCommand
    case unknownSignal(String)
    case installNeedsCommand

    public var description: String {
        switch self {
        case let .unknownCommand(name):
            return "unknown command '\(name)' — try 'dark-signal help'"
        case let .missingValue(flag):
            return "\(flag) needs a value"
        case .missingCommand:
            return "nothing to run — put the command after --"
        case let .unknownSignal(name):
            return "unknown signal '\(name)'"
        case .installNeedsCommand:
            return "install needs the command to install, e.g. 'install signal --process nvim'"
        }
    }
}

public enum Options {
    /// Signals worth reacting to a theme change with. SIGUSR1 is the conventional
    /// "reload yourself" for editors; the rest are here so nobody has to patch this
    /// list for an unusual client.
    public static let signals: [String: Int32] = [
        "USR1": SIGUSR1,
        "USR2": SIGUSR2,
        "HUP": SIGHUP,
        "WINCH": SIGWINCH,
        "INT": SIGINT,
        "TERM": SIGTERM,
    ]

    public static func signal(named name: String) -> Int32? {
        let bare = name.uppercased().hasPrefix("SIG")
            ? String(name.uppercased().dropFirst(3))
            : name.uppercased()

        return signals[bare]
    }

    public static func parse(_ arguments: [String]) throws -> Command {
        guard let first = arguments.first else {
            return .help
        }

        switch first {
        case "help", "--help", "-h":
            return .help

        case "status":
            return .status

        case "uninstall":
            return .uninstall

        case "install":
            let rest = Array(arguments.dropFirst())
            guard !rest.isEmpty else {
                throw OptionsError.installNeedsCommand
            }
            // Parsed for its side effect: refuse to install something that would
            // fail on the first run, when nobody is watching the output.
            _ = try parse(rest)
            return .install(arguments: rest)

        case "signal":
            return try parseSignal(Array(arguments.dropFirst()))

        case "exec":
            let rest = Array(arguments.dropFirst())
            let command = rest.first == "--" ? Array(rest.dropFirst()) : rest
            guard !command.isEmpty else {
                throw OptionsError.missingCommand
            }
            return .exec(command: command)

        default:
            throw OptionsError.unknownCommand(first)
        }
    }

    private static func parseSignal(_ arguments: [String]) throws -> Command {
        var process: String?
        var signalName = "USR1"
        var index = 0

        while index < arguments.count {
            switch arguments[index] {
            case "--process", "-p":
                guard index + 1 < arguments.count else {
                    throw OptionsError.missingValue("--process")
                }
                process = arguments[index + 1]
                index += 2

            case "--signal", "-s":
                guard index + 1 < arguments.count else {
                    throw OptionsError.missingValue("--signal")
                }
                signalName = arguments[index + 1]
                index += 2

            default:
                // A bare word is the process name, so `signal nvim` works too
                process = arguments[index]
                index += 1
            }
        }

        guard let name = process, !name.isEmpty else {
            throw OptionsError.missingValue("--process")
        }

        guard let number = signal(named: signalName) else {
            throw OptionsError.unknownSignal(signalName)
        }

        return .signal(process: name, signal: number)
    }
}
