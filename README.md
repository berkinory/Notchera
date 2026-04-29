# Notchera

> Native notch companion for macOS.

Notchera turns the notch area into a compact interaction layer for media, system feedback, quick actions, and utility workflows.

## Features

- Hover-to-open notch UI
- Multi display support
- Media controls with live activity style playback
- Custom HUD for volume, brightness, backlight, focus, battery, recording, and Bluetooth audio
- File shelf with drag-to-notch interaction
- Clipboard history
- Command launcher with app search, calculator, and currency conversion
- Calendar view for upcoming events
- AI usage tracking for Claude and Codex accounts
- Global shortcuts
- `notcherahud` CLI for external HUD events

## Installation

### Homebrew

```bash
brew install --cask berkinory/brew/notchera
```

### Direct Install

Download the latest DMG from [GitHub Releases](https://github.com/berkinory/Notchera/releases).

## Permissions


| Permission | Purpose |
| --- | --- |
| Accessibility | HUD replacement, keyboard flows, clipboard paste-on-select, and system interaction hooks |
| Calendar | Upcoming events |

## CLI

`notcherahud` sends external HUD payloads to the app through distributed notifications.

### Supported item flags

| Flag | Value | Type |
| --- | --- | --- |
| `--left-icon` | `string` | `icon` |
| `--left-text` | `string` | `text` |
| `--left-value` | `number` | `value` |
| `--left-slider` | `0...1` | `slider` |
| `--left-loading` | none | `loading` |
| `--left-spinner` | none | `spinner` |
| `--right-icon` | `string` | `icon` |
| `--right-text` | `string` | `text` |
| `--right-value` | `number` | `value` |
| `--right-slider` | `0...1` | `slider` |
| `--right-loading` | none | `loading` |
| `--right-spinner` | none | `spinner` |

### Shared flags

| Flag | Value | Notes |
| --- | --- | --- |
| `--duration` | `milliseconds` | clamped to `500...2500` |
| `--color` | token or hex | applies to the most recently added item |
| `--help`, `-h` | none | prints help |

### Color values

**Tokens**

- `primary`
- `secondary`
- `green`
- `yellow`
- `red`
- `blue`

**Hex**

- `#RRGGBB`
- `#RRGGBBAA`

### Constraints

- Left side supports up to `2` items
- Right side supports up to `3` items
- At least one item is required
- Flag order defines render order
- Each item can have its own color

### Example

```bash
notcherahud \
  --duration 1800 \
  --left-icon bolt.fill \
  --color yellow \
  --left-text "build" \
  --color "#F8FAFC" \
  --right-slider 0.72 \
  --color "#3B82F6" \
  --right-value 72 \
  --color secondary
```

## Development

```bash
make open    # Open Xcode project
make build   # Build app
make run     # Build and launch
make cli     # Build CLI
make check   # Format, lint, build
```

## Updates

```bash
brew update && brew upgrade --cask notchera
```

## License

See [LICENSE](./LICENSE).
