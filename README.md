# ADHDBiS - Best in Slot Addon for World of Warcraft

All-in-one BiS gear tracker, loot tracker, and raid companion addon for WoW: Midnight.

## Components

- **addon/** - WoW addon (Lua) - drop into your AddOns folder
- **updater/** - Companion app (Go) - scrapes BiS data from Icy Veins / Wowhead
- **www/** - Website for downloads and documentation

## Quick Start

1. Copy `addon/` contents to `World of Warcraft/_midnight_/Interface/AddOns/ADHDBiS/`
2. Run the updater for your platform to download BiS data
3. Type `/reload` in WoW, then `/adhd bis` to open

## Commands

| Command | Description |
|---------|-------------|
| `/adhd bis` | Toggle BiS panel |
| `/adhd loot` | Toggle Loot Tracker |
| `/adhd loot new` | New loot session |
| `/adhd loot help` | All loot commands |
| `/adhd minimap hide/show/reset` | Control minimap button |
| `/adhd version` | Show addon version |

## License

MIT

