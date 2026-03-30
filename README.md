# Checkpoint

A macOS menu bar app that gives you a visual approval UI for Claude Code tool calls.

When Claude Code wants to run a command, edit a file, or fetch a URL, this app intercepts the request and shows a prompt in your menu bar. You can allow, deny, or grant session-wide permission.

## How it works

1. On launch, the app starts an HTTP server on a local port and registers a `PreToolUse` hook in `~/.claude/settings.json`
2. When Claude Code invokes a matched tool, it sends the request to the app
3. A notification appears and the menu bar icon shows a countdown
4. You approve or deny from the menu bar popover (or from the notification actions)
5. On quit, the hook is cleanly removed from settings

## Intercepted tools

The hook matches tools that modify state or reach external services:

- **File mutation** — `Edit`, `Write`, `MultiEdit`, `NotebookEdit`
- **Shell** — `Bash`
- **Network** — `WebFetch`, `WebSearch`
- **Extensibility** — `Skill`, `mcp__*` (all MCP server tools)

Read-only tools (`Read`, `Glob`, `Grep`, `LSP`, etc.) pass through without prompting.

## Menu bar states

| Icon | Meaning |
|------|---------|
| `checkmark.shield` | Server running, no pending requests |
| `exclamationmark.shield` + ring | Request pending, countdown active |
| `shield.slash` | Server not running |

## Session rules

Clicking **Always Allow** on a request creates a session rule like `Bash(npm *)` or `Edit(**/*.tsx)`. All future matching requests from that session are auto-approved. Active rules are listed in the menu bar popover and can be revoked individually.

## Requirements

- macOS 14+
- Xcode 15+
- [mise](https://mise.jdx.dev) (installs XcodeGen and SwiftLint automatically)

## Project structure

```
Sources/
  App/                  # App entry point and AppDelegate
  Models/               # PermissionRequest, PermissionResponse, JSONValue
  Server/               # TCP server handling HTTP hook requests
  Services/             # HookConfigManager (settings.json), NotificationManager
  ViewModels/           # PermissionManager (state, session rules, request lifecycle)
  Views/                # MenuBarIconView, PermissionListView, PermissionDetailView
Tests/
  ...                   # Unit tests for models, services, and view models
```

## Building

The Xcode project is generated from `project.yml` via [XcodeGen](https://github.com/yonaskolb/XcodeGen). If you have [mise](https://mise.jdx.dev) installed, it handles tool versions automatically:

```sh
mise install          # install XcodeGen + SwiftLint
mise run generate     # generate Checkpoint.xcodeproj
mise run build        # build the app
```

Or manually:

```sh
xcodegen generate
xcodebuild -project Checkpoint.xcodeproj -scheme Checkpoint -configuration Release build
```

> **Note:** The app runs without App Sandbox because it needs to read/write `~/.claude/settings.json` and bind a local TCP port for the hook server.

## License

MIT
