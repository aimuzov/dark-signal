import DarkSignalCore
import Foundation

// A plain executable rather than XCTest: the Command Line Tools ship no XCTest, and a
// suite that only runs where Xcode is installed is a suite that stops being run.
//
//   swift run dark-signal-tests

var passed = 0
var failed = 0

func check(_ name: String, _ condition: Bool) {
    if condition {
        passed += 1
        print("ok \(passed + failed) — \(name)")
    } else {
        failed += 1
        print("not ok \(passed + failed) — \(name)")
    }
}

func check<T: Equatable>(_ name: String, _ actual: T, _ expected: T) {
    let ok = actual == expected
    check(name, ok)
    if !ok {
        print("  expected: \(expected)")
        print("  actual:   \(actual)")
    }
}

func checkThrows(_ name: String, _ expected: OptionsError, _ body: () throws -> Command) {
    do {
        let value = try body()
        check(name, false)
        print("  expected error \(expected), got \(value)")
    } catch let error as OptionsError {
        check(name, error, expected)
    } catch {
        check(name, false)
        print("  unexpected error: \(error)")
    }
}

// MARK: - Option parsing

check("signal defaults to USR1", try? Options.parse(["signal", "--process", "nvim"]), .signal(process: "nvim", signal: SIGUSR1))
check("the process name may be bare", try? Options.parse(["signal", "nvim"]), .signal(process: "nvim", signal: SIGUSR1))
check("a signal name is taken with or without the SIG prefix", Options.signal(named: "sigusr2"), SIGUSR2)
check("an unknown signal name resolves to nothing", Options.signal(named: "BANANA") == nil)

checkThrows("an unknown signal is rejected", .unknownSignal("BANANA")) {
    try Options.parse(["signal", "nvim", "--signal", "BANANA"])
}

checkThrows("signal without a process is rejected", .missingValue("--process")) {
    try Options.parse(["signal"])
}

check(
    "exec takes the command after the separator",
    try? Options.parse(["exec", "--", "fish", "-c", "change_background"]),
    .exec(command: ["fish", "-c", "change_background"])
)
check("exec works without the separator", try? Options.parse(["exec", "true"]), .exec(command: ["true"]))

checkThrows("exec needs something to run", .missingCommand) {
    try Options.parse(["exec", "--"])
}

// Installing a broken command line would fail on its first run inside launchd, where
// nobody sees the error, so it is refused while the user is still watching.
checkThrows("install refuses a command it could not run", .unknownSignal("BANANA")) {
    try Options.parse(["install", "signal", "nvim", "--signal", "BANANA"])
}

check(
    "install keeps its arguments verbatim",
    try? Options.parse(["install", "signal", "--process", "nvim"]),
    .install(arguments: ["signal", "--process", "nvim"])
)

checkThrows("install needs something to install", .installNeedsCommand) {
    try Options.parse(["install"])
}

check("no arguments is help", try? Options.parse([]), .help)

checkThrows("an unknown command is rejected", .unknownCommand("dance")) {
    try Options.parse(["dance"])
}

// MARK: - Appearance

// macOS spells light mode as the absence of the key, not as "Light"
check("a missing AppleInterfaceStyle means light", AppearanceReader.appearance(from: nil), .light)
check("Dark means dark", AppearanceReader.appearance(from: "Dark"), .dark)
check("the value is compared case-insensitively", AppearanceReader.appearance(from: "dark"), .dark)
check("dark exports DARKMODE=1", Appearance.dark.environmentValue, "1")
check("light exports DARKMODE=0", Appearance.light.environmentValue, "0")
check("the current appearance can be read", [Appearance.dark, .light].contains(AppearanceReader.current()))

// MARK: - LaunchAgent

let plist = Agent.plist(binary: "/opt/homebrew/bin/dark-signal", arguments: ["signal", "nvim"])

check("the agent points at the binary and its arguments",
      plist["ProgramArguments"] as? [String] ?? [],
      ["/opt/homebrew/bin/dark-signal", "signal", "nvim"])
check("the agent runs at load", plist["RunAtLoad"] as? Bool == true)
check("the agent is kept alive", plist["KeepAlive"] as? Bool == true)

// launchctl looks the agent up by label, and the file has to be named after it
check("the plist file is named after the label",
      Agent.plistURL(home: URL(fileURLWithPath: "/Users/someone")).path,
      "/Users/someone/Library/LaunchAgents/\(Agent.label).plist")

if let data = try? Agent.plistData(binary: "/usr/local/bin/dark-signal", arguments: ["status"]),
   let parsed = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
    check("the written plist parses back",
          parsed["ProgramArguments"] as? [String] ?? [],
          ["/usr/local/bin/dark-signal", "status"])
} else {
    check("the written plist parses back", false)
}

// MARK: - Processes

if let own = Processes.name(of: getpid()) {
    check("a process can be named", !own.isEmpty)
    // Signalling yourself is never what the user meant, so the own pid is filtered out
    check("the current process is not among its own matches", !Processes.pids(named: own).contains(getpid()))
} else {
    check("a process can be named", false)
}

check("a name nothing runs under matches nothing", Processes.pids(named: "definitely-not-a-process").isEmpty)
check("an exact name matches", Processes.matches("nvim", "nvim"))
check("a different name does not", !Processes.matches("nvim", "vim"))
// The kernel cuts long names off, so the full name still has to find its process
check("a name cut off at the limit matches the full one",
      Processes.matches("com.apple.WebKit.WebContent.Enh", "com.apple.WebKit.WebContent.EnhancedSecurity"))
check("a short name is not treated as a prefix", !Processes.matches("nvim", "nvimpager"))

print("")
print("\(passed + failed) checks, \(failed) failed")
exit(failed == 0 ? 0 : 1)
