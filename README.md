# Claude Token Monitor

A macOS menu bar app that displays your Claude Code token usage statistics.

## Features

- **Menu Bar Display**: Shows today's token count directly in the menu bar
- **Daily/Weekly/Monthly Stats**: View your token usage for different time periods
- **Weekly Chart**: Visual chart showing daily token usage for the current week
- **Auto-refresh**: Updates every 60 seconds automatically

## Screenshot

The app displays:
- A brain icon with today's token count in the menu bar
- Detailed statistics panel with daily, weekly, and monthly totals
- A bar chart showing the weekly usage breakdown

## Installation

### Prerequisites

- macOS 14.0 or later
- Xcode 15.0 or later
- [xcodegen](https://github.com/yonaskolb/XcodeGen) (optional, for regenerating the project)

### Build from Source

```bash
# Clone and build
cd claude-monitor
make build

# Run
make run

# Install to /Applications
make install
```

### Open in Xcode

```bash
make xcode
```

## Data Source

The app reads token usage data from `~/.claude/projects/` directory, parsing all `.jsonl` files recursively. It looks for messages with `type: "assistant"` and extracts token counts from the `usage` field.

Token types tracked:
- Input tokens
- Output tokens
- Cache creation tokens
- Cache read tokens

## Project Structure

```
ClaudeMonitor/
├── ClaudeMonitorApp.swift     # Main app entry point
├── Models/
│   └── TokenUsage.swift       # Data models
├── Services/
│   ├── TokenParser.swift      # JSONL file parser
│   └── TokenService.swift     # Token aggregation service
├── Views/
│   ├── MenuBarView.swift      # Main menu bar view
│   └── SettingsView.swift     # Settings window
├── Assets.xcassets/           # App icons
├── Info.plist                 # App configuration
└── ClaudeMonitor.entitlements # App entitlements
```

## License

MIT
