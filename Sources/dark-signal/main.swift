import DarkSignalCore
import Foundation
import MachO

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("dark-signal: \(message)\n".utf8))
    exit(1)
}

/// argv[0] is whatever the caller typed, so the real path is asked of dyld — the
/// LaunchAgent must point at the binary, not at the word "dark-signal".
func executablePath() -> String {
    var size = UInt32(PATH_MAX)
    var buffer = [CChar](repeating: 0, count: Int(size))

    guard _NSGetExecutablePath(&buffer, &size) == 0 else {
        return CommandLine.arguments[0]
    }

    let path = String(cString: buffer)
    return URL(fileURLWithPath: path).resolvingSymlinksInPath().path
}

@discardableResult
func launchctl(_ arguments: [String]) -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    process.arguments = arguments
    process.standardError = FileHandle.nullDevice
    process.standardOutput = FileHandle.nullDevice

    do {
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    } catch {
        return 1
    }
}

func install(arguments: [String]) -> Never {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let url = Agent.plistURL(home: home)

    do {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Agent.plistData(binary: executablePath(), arguments: arguments).write(to: url)
    } catch {
        fail("could not write \(url.path): \(error)")
    }

    let domain = "gui/\(getuid())"
    // Replacing an agent means removing the old one first; it may not be there
    launchctl(["bootout", "\(domain)/\(Agent.label)"])

    guard launchctl(["bootstrap", domain, url.path]) == 0 else {
        fail("wrote \(url.path) but launchctl refused to load it")
    }

    print("installed: \(url.path)")
    print("running:   dark-signal \(arguments.joined(separator: " "))")
    exit(0)
}

func uninstall() -> Never {
    let url = Agent.plistURL(home: FileManager.default.homeDirectoryForCurrentUser)

    launchctl(["bootout", "gui/\(getuid())/\(Agent.label)"])
    try? FileManager.default.removeItem(at: url)

    print("removed: \(url.path)")
    exit(0)
}

let usage = """
dark-signal — react to macOS switching between light and dark.

Usage:
  dark-signal signal --process nvim --signal USR1   signal every process with that name
  dark-signal exec -- fish -c change_background     run a command with $DARKMODE set
  dark-signal install signal --process nvim         keep the above running via a LaunchAgent
  dark-signal uninstall                             remove that LaunchAgent
  dark-signal status                                print the current appearance and exit

Both watching modes fire once at start-up as well, so a client that missed a change
while nothing was running catches up immediately.

Signals: USR1 (default), USR2, HUP, WINCH, INT, TERM.
"""

let command: Command

do {
    command = try Options.parse(Array(CommandLine.arguments.dropFirst()))
} catch {
    fail("\(error)")
}

switch command {
case .help:
    print(usage)

case .status:
    print(AppearanceReader.current().rawValue)

case .install(let arguments):
    install(arguments: arguments)

case .uninstall:
    uninstall()

case let .signal(process, number):
    Watcher { _ in
        Processes.send(number, toProcessesNamed: process)
    }.run()

case let .exec(command):
    Watcher { appearance in
        Executor.run(command, appearance: appearance)
    }.run()
}
