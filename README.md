# ClaudeStatus

A macOS menu bar indicator for Claude Code. When you have many sessions open, it shows at a glance how many are working and which ones are waiting for you.

```
✳ 2  ✋ 1  ✓ 3
```

| Display | Meaning |
|---|---|
| `✳ 2` | 2 sessions are running (Claude is thinking or using tools) |
| `✋ 1` | 1 session is blocked, waiting for you to approve a permission or answer a question (orange) |
| `✓ 3` | 3 sessions have finished and are waiting for your next instruction |
| `✳ ?` | Session data cannot be read, see [Troubleshooting](#troubleshooting) |

Counts of zero are hidden, so when everything is idle you see only `✳`.

## Coverage

| Source | Supported |
|---|---|
| Claude Code CLI | ✓ |
| Claude Code VS Code extension | ✓ |
| Claude Desktop, Code tab | ✓ |
| Claude Desktop, chat and Cowork | ✗ |

Chat replies are generated in the cloud and Cowork runs inside a VM, so neither leaves any state on the Mac that could be read.

## Install

Requires macOS 14.4 or later, and Xcode (or a Swift toolchain) to build.

```bash
./scripts/build-app.sh            # creates build/ClaudeStatus.app
open build/ClaudeStatus.app       # start it
```

To start it automatically at login:

```bash
./scripts/login-item.sh install     # install and start now
./scripts/login-item.sh uninstall   # remove and stop
```

This writes a LaunchAgent to `~/Library/LaunchAgents/local.claude-status.plist` that holds the absolute path of the app. Run `install` again in these two cases:

- The project folder has moved.
- You have rebuilt the app. The running copy is still the old build, and reinstalling replaces it.

## Usage

Click the icon to open the list. Sessions are grouped by state, and each row shows the folder name and the source:

```
Blocked
  ✋ my-app · VS Code — needs permission
Running
  ● api-server · CLI
Done
  ✓ docs · Desktop
────────────
Clear Done Sessions
Quit
```

- **Click a session** to jump to its window. If it is under Done, it also counts as seen and leaves the list.
- **Clear Done Sessions** removes every session currently under Done. It appears only when there is at least one.
- **Quit** closes ClaudeStatus until the next login.

Idle sessions are not listed.

### When a session counts as done

- **It appears** when ClaudeStatus sees a session go from running or blocked to idle.
- **It disappears** when you send that session another instruction, close it, click it in the list, or choose Clear Done Sessions.

Sessions that were already idle when ClaudeStatus started are not marked as done, so panels that are open but unused stay out of the list.

### How precise the jump is

| Source | Jumps to |
|---|---|
| VS Code | The right window and session tab |
| CLI in iTerm2 | The right window and tab |
| CLI in another terminal | That terminal app |
| Claude Desktop | The Claude app |

The first jump to iTerm2 makes macOS ask whether ClaudeStatus may control iTerm2. Allow it.

## How it works

Claude Code keeps a `~/.claude/sessions/<pid>.json` file for every live session and rewrites it whenever the state changes. ClaudeStatus only reads that directory:

| `status` in the file | Treated as |
|---|---|
| `busy` | Running |
| `waiting` | Blocked |
| `idle`, `shell`, anything else | Idle |

- The directory is watched with FSEvents, so changes show up within about 0.2 seconds. It is also rescanned every 5 seconds.
- Files whose process no longer exists are ignored. The process start time is compared too, so another process that reuses the same PID is not mistaken for the session.
- It does not use Claude Code hooks and does not modify `~/.claude/settings.json`.
- It does not read the `.key` files in the same directory.

## Known limitations

- A session interrupted with Esc is also listed under Done, because the state file cannot tell an interrupt from a normal finish.
- For Claude Desktop it can only switch to the app, not to a specific session.
- The done marks are kept in memory and are lost when ClaudeStatus restarts.
- Background sessions (`claude --bg`) have not been tested.
- The file format in `~/.claude/sessions/` is undocumented and may change in a Claude Code update.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| The icon shows `✳ ?` | `~/.claude/sessions/` cannot be read. Check that the directory exists. It is created the first time Claude Code runs. |
| "⚠ Cannot read N session files" at the top of the list | Some files keep failing to parse, most likely because a Claude Code update changed the format. |
| The numbers look wrong | Run `claude agents --json` to compare. It reads the same data. |
| Two icons in the menu bar | Two copies are running. `./scripts/login-item.sh install` removes the extra one. |

## Development

```bash
swift test                 # unit tests
./scripts/build-app.sh     # build and package
```

```
Sources/ClaudeStatusCore/        Pure logic with no UI dependency, covered by unit tests
  Session.swift                  Session file model and state classification
  SessionLoader.swift            Parses the directory contents, handles half-written files
  SessionTracker.swift           State machine for the done marks
Sources/ClaudeStatus/            The menu bar app
  main.swift                     Entry point
  SessionReader.swift            Reads and watches the directory, checks process liveness
  StatusItemController.swift     Icon and dropdown list
  Jumper.swift                   Jumps to the window of each source
Tests/ClaudeStatusCoreTests/     Unit tests
Resources/Info.plist             App bundle settings
scripts/build-app.sh             Build, package and sign
scripts/login-item.sh            Install or remove start at login
```
