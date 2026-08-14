# CLAUDE.md — dark-signal

## What this is

A macOS command-line tool that watches for light/dark switches and reacts: either by signalling a
running program (`signal`) or by running a command (`exec`). It also writes and loads its own
LaunchAgent (`install`), which is the part the neighbouring tools leave to the user.

It grew out of a personal Swift watcher that hardcoded "send SIGUSR1 to every nvim". The neighbours
are [dark-mode-notify](https://github.com/bouk/dark-mode-notify) and
[dark-notify](https://github.com/cormacrelf/dark-notify); the README says plainly what is different
here, and that difference is the reason the project exists — keep it honest if the neighbours change.

## Layout

```
Sources/DarkSignalCore/   Options, Appearance, Processes, Agent, Watcher — everything testable
Sources/dark-signal/      main.swift: argument dispatch, launchctl, plist writing
Sources/dark-signal-tests/ the checks, as a plain executable
```

## Conventions

- macOS 13+, Swift 5.9 tools. Code, comments and user-facing strings in English.
- Comment what the code cannot say: kernel quirks, why an API is used instead of an obvious one.
- No dependencies. The point is a single binary that a LaunchAgent can run.

## Traps already hit (do not re-discover these)

- **`proc_listallpids` answers in pids, not bytes**, despite the "buffersize" wording of its
  argument. Dividing the result by `sizeof(pid_t)` silently drops three quarters of the process
  table — the symptom is a signal that never arrives for a process that is plainly running.
- **`proc_name` needs a buffer of `2 * MAXCOMLEN + 1`.** With `MAXCOMLEN + 1` it writes nothing and
  returns 0. Names come back cut at 31 characters, so a longer name has to be matched on that
  prefix (`Processes.matches`).
- **Light mode is the absence of a key**, not `AppleInterfaceStyle = "Light"`.
- **The appearance must be re-read through `CFPreferencesAppSynchronize`.** A long-lived process that
  reads `UserDefaults` keeps answering with the value from when it started.
- **XCTest is not in the Command Line Tools.** The checks are an executable target for that reason;
  `swift test` fails on a machine without Xcode, `swift run dark-signal-tests` does not.
- **A luv signal handle must be kept in a variable** on the nvim side, or it is collected and the
  signal goes nowhere. The README example does this; keep it that way.
- **nvim survives an unhandled SIGUSR1** (libuv installs a handler), so a missing listener is a
  no-op rather than a lost session — verified, and worth remembering before "fixing" it.

## Testing

```sh
swift run dark-signal-tests
```

What the checks cannot cover is the notification itself: firing it means changing the system
appearance. What was verified by hand instead, and is worth repeating after touching `Watcher` or
`Processes`:

```sh
# the start-up call reaches an exec command
dark-signal exec -- sh -c 'echo $DARKMODE >> /tmp/dm.log'

# the signal reaches a process by name
/bin/sleep 30 & dark-signal signal --process sleep --signal TERM

# end to end, with a listener
nvim --headless -u NONE -c 'luafile signal-handler.lua' & dark-signal signal --process nvim
```

Note that `sleep` on a machine with coreutils in front of the PATH is `gsleep` — the kernel reports
the real name, which is why the check above uses `/bin/sleep` explicitly.
