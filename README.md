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

## Features

- BiS gear, enchants, gems, consumables and talent builds for all 13 classes / 40 specs
- Loot Tracker with category filters (Gear, Mounts, Recipes, Consumables)
- Wishlist system - right-click items in BiS panel or Loot Tracker to bookmark them
- Golden glow on BiS and wishlisted items in the Loot Tracker
- Upgrade detection - shows which loot drops are upgrades for you
- Data from both Icy Veins and Wowhead with in-game source switching

## Commands

| Command | Description |
|---------|-------------|
| `/adhd bis` | Toggle BiS panel |
| `/adhd loot` | Toggle Loot Tracker |
| `/adhd loot new` | New loot session |
| `/adhd loot wishlist` | Show wishlisted items |
| `/adhd loot sound` | Change BiS/wishlist alert sound |
| `/adhd loot help` | All loot commands |
| `/adhd minimap hide/show/reset` | Control minimap button |
| `/adhd version` | Show addon version |

## License

MIT

