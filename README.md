# dark-signal

Reacts to macOS switching between light and dark: signals a running program, or runs a command.

```sh
dark-signal signal --process nvim --signal USR1    # tell every nvim to reload its colours
dark-signal exec -- fish -c change_background      # run something with $DARKMODE set
dark-signal install signal --process nvim          # keep that running, across logins
```

## Why another one of these

[dark-mode-notify](https://github.com/bouk/dark-mode-notify) and
[dark-notify](https://github.com/cormacrelf/dark-notify) both do one thing: run a command when the
appearance changes. That leaves two chores to whoever wants an editor to follow the system theme —
writing a script that finds the running instances and signals them, and hand-writing a LaunchAgent
plist to keep the watcher alive.

`dark-signal` does those two itself:

- **`signal` mode**, because "tell the program that is already running" is the common case. Process
  lookup goes through libproc, not `pgrep`, so it also works under launchd where `PATH` is short.
- **`install` / `uninstall`**, which generate the LaunchAgent from the binary that is actually
  running and load it with `launchctl`. No plist to copy, no path to keep in sync after an upgrade.

If all you need is "run this command", any of the three will do, and the other two have been around
longer.

## Install

Requires macOS 13+ and a Swift toolchain (the Command Line Tools are enough).

```sh
git clone https://github.com/aimuzov/dark-signal
cd dark-signal
swift build -c release
cp .build/release/dark-signal /usr/local/bin/
```

## Usage

```
dark-signal signal --process nvim --signal USR1   signal every process with that name
dark-signal exec -- fish -c change_background     run a command with $DARKMODE set
dark-signal install signal --process nvim         keep the above running via a LaunchAgent
dark-signal uninstall                             remove that LaunchAgent
dark-signal status                                print the current appearance and exit
```

- `--signal` takes `USR1` (the default), `USR2`, `HUP`, `WINCH`, `INT` or `TERM`, with or without
  the `SIG` prefix.
- `--process` may be given as a bare word: `dark-signal signal nvim`.
- `exec` runs the command with `DARKMODE=1` or `DARKMODE=0`, the convention the neighbouring tools
  use, and with `DARK_SIGNAL_APPEARANCE=dark|light` for readability.

**Both watching modes fire once at start-up**, not only on later changes. A machine that switched to
dark while nothing was watching — overnight, or before login — catches up immediately instead of
staying on the wrong theme until the next switch.

`install` takes exactly the arguments you would have typed, checks them, and only then writes the
agent: a command line that would fail on its first run is refused while you can still see the error,
rather than failing silently inside launchd.

## Making nvim listen

Nothing here is nvim-specific, but that is the case it was written for. In your config:

```lua
-- Keep the handle in a variable: a signal watcher that nothing references can be
-- collected, and the signal then goes nowhere.
local signal = vim.uv.new_signal()

signal:start("sigusr1", function()
    vim.schedule(function()
        local style = vim.fn.system("defaults read -g AppleInterfaceStyle 2>/dev/null")
        vim.o.background = style:match("Dark") and "dark" or "light"
    end)
end)
```

The callback runs on the event loop, where the Neovim API is off limits — hence the
`vim.schedule`.

Then:

```sh
dark-signal install signal --process nvim
```

## Notes

- The appearance is read from `AppleInterfaceStyle`, which macOS *removes* in light mode rather than
  setting to "Light".
- Process names are compared against what the kernel reports, which is cut off at 31 characters; a
  longer name still matches on that prefix.
- The agent is labelled `com.github.aimuzov.dark-signal` and lives in `~/Library/LaunchAgents`.

## Tests

```sh
swift run dark-signal-tests
```

The checks are a plain executable rather than an XCTest target on purpose: the Command Line Tools
ship no XCTest, and a suite that only runs where Xcode is installed stops being run.

## License

[MIT](LICENSE)
