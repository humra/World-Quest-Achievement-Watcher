# World Quest Achievement Watcher Changelog

## 1.0.0 - 2026-08-25

Initial public release of **World Quest Achievement Watcher**.

### New standalone identity

- Renamed the addon, TOC, internal AceAddon namespace, minimap/data-broker registration, tooltip/frame identifiers, settings registration, and SavedVariables so it can coexist with the original WQAchievements addon.
- New SavedVariables database: `WQAWDB`.
- New slash command: `/wqaw`.
- CurseForge project ID: `1667887`.

### Retail 12.1.0 compatibility

- Updated the Retail interface version to `120100`.
- Fixed Midnight expansion registration and sparse zone iteration.
- Fixed reward-cache behavior so one unavailable reward cannot block the entire active-quest scan.
- Fixed Blizzard Settings opening from the minimap icon using the numeric settings category ID.
- Removed expensive full rescans from minimap-tooltip hover.
- Improved achievement criterion completion handling and quest-ID matching using live criterion asset IDs.
- Hardened optional All The Things integration so errors inside ATT cannot interrupt quest or mission scans.
- ATT lookup failures no longer force the global reward cache into a retry loop.
- CanIMogIt can be used as a fallback when ATT is installed but its lookup fails or returns no result.

### Midnight support

Added rotation-aware tracking for relevant Midnight achievement content, including:

- Slayer's Rise achievement world quests
- Val and Naigtal Showdowns
- Special Assignments
- Runestone Rush and Abundance
- Void Assaults and Ritual Sites
- Stormarion Assault
- Cursed Surges on The Coiled Isle
- Vaults of Atal'Utek Patrols, Strikes, Incursions, and Ancient Foes

Cursed Surges can be detected from the active outdoor-scenario state when Blizzard does not expose the underway event through the normal map/event feeds.
