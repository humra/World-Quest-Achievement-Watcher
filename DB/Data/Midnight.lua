local WQA = WorldQuestAchievementWatcher

-- Midnight
local data = {
    name = _G.EXPANSION_NAME11
}
WQA.data[12] = data

-- Slayer's Rise PvP world quests. Both achievements use the same seven
-- rotating world quests; Investigating the Rise requires each once, while
-- Uprising requires repeated completions of each criterion.
local slayersRisePvP = {
    { 89267 }, -- Mysterious Entity
    { 88679 }, -- Encountering the Unexpected
    { 88992 }, -- Envisioned Mastery
    { 89347 }, -- Overcoming the Unknown: Rage-Riddled Drifter
    { 87759 }, -- Encapsulated Void
    { 91419 }, -- Elemental Dominance
    { 89377 }  -- Undercover Hunt
}

-- Val Void Invasion world quests.
local valShowdown = {
    { 96400 }, -- Lingering Corruption
    { 95403 }, -- A Lingering Echo
    { 95401 }, -- Junction Dysfunction
    { 95399 }, -- Shadowy Strategies
    { 95397 }, -- Cold Reception
    { 95395 }, -- Until it is Done
    { 95393 }, -- Caver Savior
    { 95404 }, -- Freeze Range Eggs
    { 95402 }, -- Ignoble Gas Collector
    { 95400 }, -- Solid Cold
    { 95398 }, -- Dissent and Divide
    { 95396 }, -- Tainted Ritual
    { 95394 }, -- Aberration Liberation
    { 95392 }  -- One Friend is Plenty
}

-- Naigtal Void Invasion world quests.
local naigtalShowdown = {
    { 96293 }, -- Mush-Vroom!
    { 96210 }, -- Scrubbing Troubles
    { 96217 }, -- Sporadic Power Drain
    { 96000 }, -- Skiff Joyride
    { 96600 }, -- Crypt Culling
    { 96623 }, -- Capsized Compost
    { 96272 }, -- Mashing Mushroom Mana Machines
    { 96432 }, -- Power Overload
    { 96268 }, -- Marsh Mana Spores
    { 95575 }, -- Forest Mana Spores
    { 96547 }, -- Weaken Their Forces
    { 96557 }  -- Flying Debris
}

-- Heroic: Worlds Ahead uses the combined Val/Naigtal world-quest pool.
-- Live 12.1.0 client criteria confirm all 26 quests, including Capsized Compost.
local heroicWorldsAhead = {
    { 96293 }, -- Mush-Vroom!
    { 96210 }, -- Scrubbing Troubles
    { 96217 }, -- Sporadic Power Drain
    { 96000 }, -- Skiff Joyride
    { 96600 }, -- Crypt Culling
    { 96623 }, -- Capsized Compost
    { 96400 }, -- Lingering Corruption
    { 95403 }, -- A Lingering Echo
    { 95401 }, -- Junction Dysfunction
    { 95399 }, -- Shadowy Strategies
    { 95397 }, -- Cold Reception
    { 95395 }, -- Until it is Done
    { 95393 }, -- Caver Savior
    { 96557 }, -- Flying Debris
    { 96272 }, -- Mashing Mushroom Mana Machines
    { 96432 }, -- Power Overload
    { 96268 }, -- Marsh Mana Spores
    { 95575 }, -- Forest Mana Spores
    { 96547 }, -- Weaken Their Forces
    { 95404 }, -- Freeze Range Eggs
    { 95402 }, -- Ignoble Gas Collector
    { 95400 }, -- Solid Cold
    { 95398 }, -- Dissent and Divide
    { 95396 }, -- Tainted Ritual
    { 95394 }, -- Aberration Liberation
    { 95392 }  -- One Friend is Plenty
}

-- Rotating Eversong runestone events. These are map events rather than
-- ordinary world quests, but their availability is what gates Runestone Rush.
local runestoneRush = {
    { mapID = 2395, criterionName = "Elrendar River Runestone", patterns = { "Elrendar River Runestone" } },
    { mapID = 2395, criterionName = "Dawnstar Spire Runestone", patterns = { "Dawnstar Spire Runestone" } },
    { mapID = 2395, criterionName = "Sunstrider Isle Runestone", patterns = { "Sunstrider Isle Runestone" } },
    { mapID = 2395, criterionName = "Ath'ran Runestone", patterns = { "Ath'ran Runestone" } },
    { mapID = 2395, criterionName = "Sanctum of the Moon Runestone", patterns = { "Sanctum of the Moon Runestone" } }
}

-- Abundance rotates between four Midnight locations. Map-specific matching
-- means the currently active location can be surfaced only when that criterion
-- is still missing from Prosperous Plentitude.
local abundanceLocations = {
    {
        mapID = 2395,
        criterionName = { "Eversong Woods: Watha'nan Crypts", "Eversong: Wath'anan Crypts", "Watha'nan Crypts", "Wath'anan Crypts" },
        patterns = { "Abundance", "Watha'nan Crypts", "Wath'anan Crypts" }
    },
    {
        mapID = 2413,
        criterionName = { "Harandar: Floaret Grotto", "Floaret Grotto" },
        patterns = { "Abundance", "Floaret Grotto" }
    },
    {
        mapID = 2437,
        criterionName = { "Zul'Aman: Loaknit Den", "Loaknit Den" },
        patterns = { "Abundance", "Loaknit Den" }
    },
    {
        mapID = 2405,
        criterionName = { "Voidstorm: Abundant Voidburrow", "Abundant Voidburrow" },
        patterns = { "Abundance", "Abundant Voidburrow" }
    }
}

-- Void Assaults are exposed by the client as a mixture of Area POIs and
-- open-world task quests. Keep a broad set of known live event prefixes so the
-- currently active strike is detected regardless of which representation is
-- used by Blizzard.
local voidAssaultPatterns = {
    "Void Assaults", "Void Strike", "Void Incursion", "Void Rift", "Void Ritual",
    "Battery Rush", "Rage Machines", "Pylon Strike", "While We're Down",
    "Power Vacuum", "Defiled Relics", "Voidstrider Isle", "Void Strider Isle",
    "Bitter Bark", "Springclaw", "Croaker", "Grizzly"
}

local eversongVoidAssault = {
    { mapID = 2395, patterns = voidAssaultPatterns }
}

local zulAmanVoidAssault = {
    { mapID = 2437, patterns = voidAssaultPatterns }
}

local anyVoidAssault = {
    { mapID = 2395, patterns = voidAssaultPatterns },
    { mapID = 2437, patterns = voidAssaultPatterns }
}

-- Specific Void Assault rotations that are useful for the less generic
-- achievements. Names are intentionally aliases/substrings so minor title
-- variations between phases do not make the event disappear from WQA.
local cosmicExterminatorEvents = {
    { mapID = 2437, patterns = { "Void Rift: Bitter Bark", "Bitter Bark" } },
    { mapID = 2395, patterns = {
        "Void Rift: Tranquil Repose", "Tranquil Repose",
        "Void Rift: Sunstrider Isle",
        "Void Rift: South Eversong Woods", "South Eversong Woods",
        "Void Rift: Sunset Strand", "Sunset Strand"
    } }
}

local cosmicSlayerEvents = {
    { mapID = 2395, patterns = { "Void Ritual: Springclaw", "Springclaw", "Void Ritual: Croaker", "Croaker" } },
    { mapID = 2437, patterns = { "Void Ritual: Grizzly", "Grizzly" } }
}

local batteryBombardmentEvents = {
    { mapID = 2437, patterns = { "Battery Rush", "Void Incursion" } }
}

local everybodyGetsOneEvents = {
    { mapID = 2437, patterns = { "Rage Machines: Spiritpaw", "Spiritpaw Assault", "Rage Machines" } },
    { mapID = 2395, patterns = {
        "Defending Stillwhisper", "Stillwhisper", "Voidstrider Isle", "Void Strider Isle",
        "Pylon Strike: Sunstrider Isle", "Void Incursion"
    } }
}

-- Stormarion Assault runs on a timed cycle in Voidstorm. These achievements
-- are only actionable while the assault itself is running.
local stormarionAssaultEvents = {
    { mapID = 2405, patterns = { "Stormarion Assault" } }
}

-- Ritual Sites alternate weekly between Eversong Woods and Zul'Aman.
-- Pinnacle Ritual Work specifically requires both locations, so only surface
-- the currently available site if that criterion is still missing.
local pinnacleRitualSites = {
    {
        mapID = 2395,
        criterionName = "Daggerspine Point",
        patterns = { "Ritual Site: Daggerspine Point", "Daggerspine Point Ritual Site" }
    },
    {
        mapID = 2437,
        criterionName = "Broken Throne",
        patterns = { "Ritual Site: Broken Throne", "Broken Throne Ritual Site" }
    }
}

-- Traces in the Dark has hidden-item criteria. Associate the rotations that can
-- provide each item with that specific live criterion so already-finished
-- pieces do not keep generating notifications.
local tracesInTheDarkEvents = {
    {
        mapID = 2437,
        criterionName = "Consult allies about the Torn Twilight Missive",
        patterns = { "While We're Down", "Broken Throne" }
    },
    {
        mapID = 2437,
        criterionName = "Consult allies about the Hal'hadar Battery Core",
        patterns = { "Battery Rush" }
    },
    {
        mapID = 2437,
        criterionName = "Consult allies about the Enchanted Naga Scroll",
        patterns = { "Daggerspine Point" }
    },
    {
        mapID = 2437,
        criterionName = "Consult allies about the Permafrosted Keystone",
        patterns = { "Daggerspine Point", "Void Ritual: Grizzly", "Grizzly" }
    },
    {
        mapID = 2395,
        criterionName = "Consult allies about the Permafrosted Keystone",
        patterns = { "Voidstrider Isle", "Void Strider Isle", "Pylon Strike: Sunstrider Isle" }
    }
}


-- Patch 12.1: Cursed Surges on the Coiled Isle rotate between five event
-- locations. Achievement criteria name the boss while the map event can use a
-- different title, so each criterion carries both identities.
local cursedSurgePatterns = {
    "The Looming Mutagenitor", "Looming Mutagenitor",
    "Mlurkkr Massacre", "Ss'akrithos",
    "The Malformed Leviathan", "Malformed Leviathan",
    "The Broodmother's Nest", "Vassti, the Exalted Broodmother",
    "Siege at the Whispering Marsh", "Venom Lancer Ori'kassi"
}

local turnTheSurgeEvents = {
    { mapID = 2512, criterionName = "Looming Mutagenitor", patterns = { "The Looming Mutagenitor", "Looming Mutagenitor" } },
    { mapID = 2512, criterionName = "Ss'akrithos", patterns = { "Mlurkkr Massacre", "Ss'akrithos" } },
    { mapID = 2512, criterionName = "Malformed Leviathan", patterns = { "The Malformed Leviathan", "Malformed Leviathan" } },
    { mapID = 2512, criterionName = "Vassti, the Exalted Broodmother", patterns = { "The Broodmother's Nest", "Vassti, the Exalted Broodmother" } },
    { mapID = 2512, criterionName = "Venom Lancer Ori'kassi", patterns = { "Siege at the Whispering Marsh", "Venom Lancer Ori'kassi" } }
}

local anyCursedSurge = {
    { mapID = 2512, patterns = cursedSurgePatterns }
}

local loomingMutagenitorSurge = {
    { mapID = 2512, patterns = { "The Looming Mutagenitor", "Looming Mutagenitor" } }
}

-- Six Angler of the Coiled Isle fish are tied to the Cursed Land and Waters
-- state gained from completing a Cursed Surge. Only notify for a Surge while
-- at least one of those specific fish criteria is still missing.
local cursedFishingSurges = {
    { mapID = 2512, criterionName = "Giggling Skull", patterns = cursedSurgePatterns },
    { mapID = 2512, criterionName = "Grotesque Sturgeon", patterns = cursedSurgePatterns },
    { mapID = 2512, criterionName = "Loathsome Anglerfish", patterns = cursedSurgePatterns },
    { mapID = 2512, criterionName = "Many-Eyed Flounder", patterns = cursedSurgePatterns },
    { mapID = 2512, criterionName = "Oozing Goby", patterns = cursedSurgePatterns },
    { mapID = 2512, criterionName = "Twin-Headed Snipefish", patterns = cursedSurgePatterns }
}

-- Patch 12.1: Vaults of Atal'Utek public-event rotations. The live map uses
-- map ID 2509. Patrols and Strikes rotate in pools, Incursions cycle after
-- Strikes, and only one Ancient Foe is available for the weekly rotation.
local vaultPatrols = {
    { mapID = 2509, criterionName = "Broken Bonds", patterns = { "Temple Patrol: Broken Bonds", "Broken Bonds" } },
    { mapID = 2509, criterionName = "Slay Children of Ula'tek", patterns = { "Temple Patrol: Slay Children of Ula'tek", "Slay Children of Ula'tek" } },
    { mapID = 2509, criterionName = "Scavenged Weapons", patterns = { "Temple Patrol: Scavenged Weapons", "Scavenged Weapons" } },
    { mapID = 2509, criterionName = "Congealed Venom", patterns = { "Temple Patrol: Congealed Venom", "Congealed Venom" } },
    { mapID = 2509, criterionName = "Vengeance for the Dead", patterns = { "Temple Patrol: Vengeance for the Dead", "Vengeance for the Dead" } },
    { mapID = 2509, criterionName = "Calming the Dead", patterns = { "Temple Patrol: Calming the Dead", "Calming the Dead" } },
    { mapID = 2509, criterionName = "Slay the Restless", patterns = { "Temple Patrol: Slay the Restless", "Slay the Restless" } },
    { mapID = 2509, criterionName = "Siphon Venom", patterns = { "Temple Patrol: Siphon Venom", "Siphon Venom" } },
    { mapID = 2509, criterionName = "Breath and Bile", patterns = { "Temple Patrol: Breath and Bile", "Breath and Bile" } },
    { mapID = 2509, criterionName = "Dragged Below", patterns = { "Temple Patrol: Dragged Below", "Dragged Below" } },
    { mapID = 2509, criterionName = "Ash to Ash", patterns = { "Temple Patrol: Ash to Ash", "Ash to Ash" } },
    { mapID = 2509, criterionName = "Laid to Rest", patterns = { "Temple Patrol: Laid to Rest", "Laid to Rest" } }
}

local vaultStrikes = {
    { mapID = 2509, criterionName = "Purifying Earth and Sky", patterns = { "Temple Strike: Purifying Earth and Sky", "Purifying Earth and Sky" } },
    { mapID = 2509, criterionName = "The Underbelly", patterns = { "Temple Strike: The Underbelly", "The Underbelly" } },
    { mapID = 2509, criterionName = "Overflowing Venom", patterns = { "Temple Strike: Overflowing Venom", "Overflowing Venom" } },
    { mapID = 2509, criterionName = "Ruuk'jar's Clutch", patterns = { "Temple Strike: Ruuk'jar's Clutch", "Ruuk'jar's Clutch" } },
    { mapID = 2509, criterionName = "Profane Pyres", patterns = { "Temple Strike: Profane Pyres", "Profane Pyres" } },
    { mapID = 2509, criterionName = "Cursed Depths", patterns = { "Temple Strike: Cursed Depths", "Cursed Depths" } }
}

local vaultIncursions = {
    { mapID = 2509, criterionName = "Cache of the Three", patterns = { "Temple Incursion: Cache of the Three", "Cache of the Three" } },
    { mapID = 2509, criterionName = "Summoning Ritual", patterns = { "Temple Incursion: Summoning Ritual", "Summoning Ritual" } },
    { mapID = 2509, criterionName = "Supplies Must Flow", patterns = { "Temple Incursion: Supplies Must Flow", "Supplies Must Flow" } }
}

local vaultAncientFoes = {
    { mapID = 2509, criterionName = "Congealed Malice", patterns = { "Ancient Foe: Congealed Malice", "Congealed Malice" } },
    { mapID = 2509, criterionName = "Khu'tulak", patterns = { "Ancient Foe: Khu'tulak", "Khu'tulak" } },
    { mapID = 2509, criterionName = "Susarikk", patterns = { "Ancient Foe: Susarikk", "Susarikk" } }
}

local loneWandererEvent = {
    { mapID = 2509, patterns = { "Temple Strike: Purifying Earth and Sky", "Purifying Earth and Sky" } }
}

local ritualBehaviorEvent = {
    { mapID = 2509, patterns = { "Temple Incursion: Summoning Ritual", "Summoning Ritual" } }
}

local danceWhileEveryoneWatchesEvent = {
    { mapID = 2509, patterns = { "Temple Incursion: Cache of the Three", "Cache of the Three" } }
}

local softUnderbellyEvent = {
    { mapID = 2509, patterns = { "Temple Strike: The Underbelly", "The Underbelly" } }
}

data.achievements = {
    {
        name = "Investigating the Rise",
        id = 61225,
        criteriaType = "QUESTS",
        criteria = slayersRisePvP
    },
    {
        name = "Uprising",
        id = 61226,
        criteriaType = "QUESTS",
        criteria = slayersRisePvP
    },
    {
        name = "Showdown Success: Val",
        id = 62880,
        criteriaType = "QUESTS",
        criteria = valShowdown
    },
    {
        name = "Showdown Success: Naigtal",
        id = 62882,
        criteriaType = "QUESTS",
        criteria = naigtalShowdown
    },
    {
        name = "Heroic: Worlds Ahead",
        id = 62887,
        criteriaType = "QUESTS",
        criteria = heroicWorldsAhead
    },
    {
        name = "No Time to Paws",
        id = 61219,
        criteriaType = "QUEST_SINGLE",
        criteria = 92085 -- Claw Enforcement
    },
    {
        name = "Lysikas Would Be Proud",
        id = 62105,
        criteriaType = "SPECIAL_ASSIGNMENT",
        criteria = {
            {
                name = "Special Assignment: Precision Excision",
                mapID = 2405, -- Voidstorm
                questIDs = { 93438, 94743 }
            }
        }
    },
    {
        name = "Grand Magister's Sommelier",
        id = 62187,
        criteriaType = "SPECIAL_ASSIGNMENT",
        criteria = {
            {
                name = "Special Assignment: The Grand Magister's Drink",
                mapID = 2395, -- Eversong Woods
                questIDs = { 92145, 92848 }
            }
        }
    },
    {
        name = "A Stack of Snacks",
        id = 63633,
        criteriaType = "QUEST_SINGLE",
        criteria = 94967 -- Ki'clak Snack Attack
    },

    -- Rotating Midnight world/map events
    {
        name = "Runestone Rush",
        id = 61961,
        criteriaType = "ROTATING_EVENT",
        criteria = runestoneRush
    },
    {
        name = "Abundance: Prosperous Plentitude!",
        id = 61943,
        criteriaType = "ROTATING_EVENT",
        criteria = abundanceLocations
    },
    { name = "Abundance: Treasures Aplenty", id = 62325, criteriaType = "ROTATING_EVENT", criteria = abundanceLocations },
    { name = "Abundance: Golden Opportunities", id = 62326, criteriaType = "ROTATING_EVENT", criteria = abundanceLocations },
    { name = "Abundance: Squash the Competition", id = 62329, criteriaType = "ROTATING_EVENT", criteria = abundanceLocations },
    { name = "Abundance: One Bite at a Time", id = 62330, criteriaType = "ROTATING_EVENT", criteria = abundanceLocations },
    { name = "Abundance: Drops of Prosperity", id = 62331, criteriaType = "ROTATING_EVENT", criteria = abundanceLocations },

    -- Patch 12.1 Coiled Isle Cursed Surge rotations.
    { name = "Turn the Surge", id = 63390, criteriaType = "ROTATING_EVENT", criteria = turnTheSurgeEvents },
    { name = "Cursebreaker", id = 63381, criteriaType = "ROTATING_EVENT", criteria = anyCursedSurge },
    { name = "It's Definitely Something", id = 63382, criteriaType = "ROTATING_EVENT", criteria = loomingMutagenitorSurge },
    { name = "Angler of The Coiled Isle", id = 63629, criteriaType = "ROTATING_EVENT", criteria = cursedFishingSurges },

    -- Patch 12.1 Vaults of Atal'Utek rotating public events.
    { name = "Roll the Patrol", id = 63598, criteriaType = "ROTATING_EVENT", criteria = vaultPatrols },
    { name = "Spike the Strike", id = 63600, criteriaType = "ROTATING_EVENT", criteria = vaultStrikes },
    { name = "Submerge the Incursion", id = 63599, criteriaType = "ROTATING_EVENT", criteria = vaultIncursions },
    { name = "Oppose the Foes", id = 63601, criteriaType = "ROTATING_EVENT", criteria = vaultAncientFoes },
    { name = "A Lone Wanderer", id = 62649, criteriaType = "ROTATING_EVENT", criteria = loneWandererEvent },
    { name = "Ritual Behavior", id = 62600, criteriaType = "ROTATING_EVENT", criteria = ritualBehaviorEvent },
    { name = "Dance While Everyone Watches", id = 62604, criteriaType = "ROTATING_EVENT", criteria = danceWhileEveryoneWatchesEvent },
    { name = "Soft Underbelly", id = 62601, criteriaType = "ROTATING_EVENT", criteria = softUnderbellyEvent },

    -- Void Assault zone progression. The same live strike can advance several
    -- achievements in the chain; completed achievements are filtered by the
    -- normal Register() logic before these event scans run.
    { name = "Void Assault: Eversong", id = 62498, criteriaType = "ROTATING_EVENT", criteria = eversongVoidAssault },
    { name = "Void Smasher: Eversong", id = 62507, criteriaType = "ROTATING_EVENT", criteria = eversongVoidAssault },
    { name = "Void Eradicator: Eversong", id = 62508, criteriaType = "ROTATING_EVENT", criteria = eversongVoidAssault },
    { name = "Void Bane: Eversong", id = 62509, criteriaType = "ROTATING_EVENT", criteria = eversongVoidAssault },
    { name = "Void Assault: Zul'Aman", id = 62499, criteriaType = "ROTATING_EVENT", criteria = zulAmanVoidAssault },
    { name = "Void Smasher: Zul'Aman", id = 62510, criteriaType = "ROTATING_EVENT", criteria = zulAmanVoidAssault },
    { name = "Void Eradicator: Zul'Aman", id = 62511, criteriaType = "ROTATING_EVENT", criteria = zulAmanVoidAssault },
    { name = "Void Bane: Zul'Aman", id = 62512, criteriaType = "ROTATING_EVENT", criteria = zulAmanVoidAssault },
    { name = "Outstanding in the Field", id = 62513, criteriaType = "ROTATING_EVENT", criteria = anyVoidAssault },
    { name = "Accolade to Rest", id = 62574, criteriaType = "ROTATING_EVENT", criteria = anyVoidAssault },
    { name = "Void Shmoid", id = 62568, criteriaType = "ROTATING_EVENT", criteria = anyVoidAssault },

    -- Void Assault achievements gated by particular rotating strike types.
    { name = "Cosmic Exterminator", id = 62518, criteriaType = "ROTATING_EVENT", criteria = cosmicExterminatorEvents },
    { name = "Traces in the Dark", id = 62569, criteriaType = "ROTATING_EVENT", criteria = tracesInTheDarkEvents },
    { name = "Battery Bombardment", id = 62572, criteriaType = "ROTATING_EVENT", criteria = batteryBombardmentEvents },
    { name = "Cosmic Slayer", id = 62570, criteriaType = "ROTATING_EVENT", criteria = cosmicSlayerEvents },
    { name = "Everybody Gets One", id = 62571, criteriaType = "ROTATING_EVENT", criteria = everybodyGetsOneEvents },

    -- Other Midnight rotating outdoor features.
    { name = "A Singular Problem", id = 61913, criteriaType = "ROTATING_EVENT", criteria = stormarionAssaultEvents },
    { name = "Ninety Percent is Good Enough", id = 61922, criteriaType = "ROTATING_EVENT", criteria = stormarionAssaultEvents },
    { name = "Pinnacle Ritual Work", id = 62941, criteriaType = "ROTATING_EVENT", criteria = pinnacleRitualSites }
}
