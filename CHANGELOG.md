# World Quest Achievement Watcher Changelog

## 1.1.0 - 2026-08-30

Changed the way how and when WQAW quest list is updated.
Unfortunately the only way to have it play nice with the game's interactions is by turning to manual mode of triggering a scan.
From now on it is required to open the add-on interface by clicking the minimap icon and clicking the refresh button,
or calling "/wqaw refresh" command in order to update the list.
If a quest-giver interface is opened the refresh command will wait until it is closed.
This change is made to fix the issues the add-on would cause when trying to talk to quest-giving NPCs, interacting with the quest log, or interacting with quest items.
Improvements for this system will be made in future versions in order to minimize the required user input in refreshing the list.

Minimap icon now displays the time since last full scan.
After collecting a transmog appearance from a world quest a silent refresh will run a few seconds later in order to update the add-on's quest list.
An issue where newly-appearing quests would not be grouped under the correct expansion section has been resolved.
Fixed a synchronization issue where the minimap icon and the opened window would sometimes show different quest lists.

## 1.0.5 - 2026-08-29

Removed GameTooltipTemplate references from the addon which caused secret-value tooltip taint errors.

## 1.0.4 - 2026-08-28

Fixed a few missing or mismatched references in the code.
Fixed localization strings still referring to WQA.

## 1.0.3 - 2026-08-28

Clicking on the achievement name in the add-on interface will now open the relevant achievement details.
Fixed the bug which would cause the pop-up to reopen on its own after closing it.

## 1.0.2 - 2026-08-27

Fixed the bug that would show duplicate sections for Midnight expansion after clicking on quests in the pop-up.
Fixed the lua errors which did not play nice with Blizzard's UI restrictions.

## 1.0.1 - 2026-08-25

Updated the minimap icon.

## 1.0.0 - 2026-08-25

Initial public release of **World Quest Achievement Watcher**.