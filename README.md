# World Quest Achievement Watcher

World Quest Achievement Watcher alerts you when active World of Warcraft content can advance achievements or other configured rewards.

Version 1.0.0 targets **World of Warcraft Retail 12.1.0** and includes compatibility work for current world-quest, Settings, reward-cache, Area POI, Event Scheduler, and outdoor-scenario behavior.

## Midnight coverage

Midnight tracking includes availability- or rotation-gated achievement content such as:

- Slayer's Rise world quests
- Val and Naigtal Showdowns
- achievement-related Special Assignments
- Runestone Rush and Abundance rotations
- Void Assault and Ritual Site rotations
- Stormarion Assault
- Cursed Surges on The Coiled Isle
- Vaults of Atal'Utek Patrols, Strikes, Incursions, and Ancient Foes

Completed achievements and completed criteria are filtered so the addon only reports content that can still advance your progress.

## Commands

- `/wqaw` - show currently interesting active content
- `/wqaw new` - show newly detected content
- `/wqaw popup` - show the popup view
- `/wqaw debug` - show compact troubleshooting information

Right-click the minimap icon to open World Quest Achievement Watcher settings.

## Compatibility notes

Some rotating Midnight activities are exposed by Blizzard through different APIs depending on their current state. World Quest Achievement Watcher can use normal map POIs and task quests, the Event Scheduler, and active outdoor scenarios. For example, an underway Cursed Surge can be detected from its outdoor scenario even when it is absent from the normal map/event feeds.

## Project history

World Quest Achievement Watcher is a separately named derivative of the original **WQAchievements** addon by **Urtgard**, whose CurseForge project is published as Public Domain. The original architecture and historical expansion data form the foundation of this project; Retail 12.1.0 compatibility and Midnight coverage were added for this version.

See `credits.md` for additional original-project credits.
