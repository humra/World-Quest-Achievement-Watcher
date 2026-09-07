local WQA = WorldQuestAchievementWatcher

WQA.Achievements = {}

local function SafeGetAchievementCriteriaInfo(achievementID, criteriaIndex)
    local ok, criteriaString, criteriaType, completed, quantity, reqQuantity, charName, flags, assetID, quantityString, criteriaID, eligible, duration, elapsed =
        pcall(GetAchievementCriteriaInfo, achievementID, criteriaIndex, true)

    if not ok then
        return nil
    end

    return criteriaString, criteriaType, completed, quantity, reqQuantity, charName, flags, assetID, quantityString, criteriaID, eligible, duration, elapsed
end

local function CriteriaValuesAreComplete(completed, quantity, reqQuantity)
    if completed then
        return true
    end

    -- Counter/progress criteria can report a completed amount (for example 10/10)
    -- even when the completed boolean is not sufficient for our filtering logic.
    if type(quantity) == "number" and type(reqQuantity) == "number" and reqQuantity > 0 and quantity >= reqQuantity then
        return true
    end

    return false
end

local function IsAchievementCriteriaComplete(achievementID, criteriaIndex)
    local _, _, completed, quantity, reqQuantity = SafeGetAchievementCriteriaInfo(achievementID, criteriaIndex)
    return CriteriaValuesAreComplete(completed, quantity, reqQuantity)
end

function WQA.Achievements:EnsureAchievementCriteriaAvailable()
    -- Achievement criteria can be only partially populated even though
    -- GetAchievementInfo() and achievement hyperlinks already work. Loading
    -- Blizzard_AchievementUI forces the client to populate the same criteria
    -- catalog used by the default achievement frame. Do this lazily, only when
    -- rotating-event criteria actually need to be inspected.
    if CanShowAchievementUI and not CanShowAchievementUI() then
        return false
    end

    if C_AddOns and C_AddOns.IsAddOnLoaded then
        local _, loaded = C_AddOns.IsAddOnLoaded("Blizzard_AchievementUI")
        if loaded then
            return true
        end
    end

    if C_AddOns and C_AddOns.LoadAddOn then
        pcall(C_AddOns.LoadAddOn, "Blizzard_AchievementUI")
    end

    if C_AddOns and C_AddOns.IsAddOnLoaded then
        local loadedOrLoading, loaded = C_AddOns.IsAddOnLoaded("Blizzard_AchievementUI")
        return loaded == true or loadedOrLoading == true
    end

    return true
end

function WQA.Achievements:Register(achievement, forced, forcedByMe)
    if achievement.criteriaType == "SPECIAL" then
        return
    end

    local id = achievement.id
    forced = forced or false
    forcedByMe = false

    if WQA.db.profile.achievements[id] == "disabled" then
        return
    end
    if WQA.db.profile.achievements[id] == "exclusive" and WQA.db.profile.achievements.exclusive[id] ~= WQA.playerName then
        return
    end
    if WQA.db.profile.achievements[id] == "always" then
        forced = true
    end
    if WQA.db.profile.achievements[id] == "wasEarnedByMe" then
        forcedByMe = true
    end

    local _, _, _, completed, _, _, _, _, _, _, _, _, wasEarnedByMe = GetAchievementInfo(id)
    if (achievement.notAccountwide and not wasEarnedByMe) or not completed or forced or forcedByMe then
        if achievement.criteriaType == "ACHIEVEMENT" then
            self:Register_ACHIEVEMENT(achievement, forced, forcedByMe)
        elseif achievement.criteriaType == "SPECIAL_ASSIGNMENT" then
            self:Register_SPECIAL_ASSIGNMENT(achievement)
        elseif achievement.criteriaType == "ROTATING_EVENT" then
            self:Register_ROTATING_EVENT(achievement)
        elseif achievement.criteriaType == "QUEST_SINGLE" then
            self:Register_QUEST_SINGLE(achievement)
        elseif achievement.criteriaType == "QUEST_PIN" then
            self:Register_QUEST_PIN(achievement, forced)
        elseif achievement.criteriaType == "QUEST_FLAG" then
            self:Register_QUEST_FLAG(achievement)
        else
            local achievementNumCriteria = GetAchievementNumCriteria(id)

            if achievementNumCriteria > 0 then
                for i = 1, achievementNumCriteria do
                    local _, _, _, _, _, _, _, questID = GetAchievementCriteriaInfo(id, i)
                    local criteriaCompleted = IsAchievementCriteriaComplete(id, i)

                    if not criteriaCompleted or forced then
                        if achievement.criteriaType == "QUESTS" then
                            self:Register_QUESTS(achievement, i, questID)
                        elseif achievement.criteriaType == "MISSION_TABLE" then
                            self:Register_MISSION_TABLE(achievement, i, questID)
                        elseif achievement.criteriaType == "AREA_POI" then
                            self:Register_AREA_POI(achievement, i)
                        else
                            WQA:AddRewardToQuest(questID, "ACHIEVEMENT", id)
                        end
                    end
                end
            else
                if achievement.criteriaType == "QUESTS" then
                    self:Register_QUESTS(achievement, 1)
                end
            end
        end
    end
end

function WQA.Achievements:Register_ACHIEVEMENT(achievement, forced, forcedByMe)
    for _, criteriaAchievement in pairs(achievement.criteria) do
        self:Register(criteriaAchievement, forced, forcedByMe)
    end
end


local function NormalizeAssignmentName(name)
    if type(name) ~= "string" then
        return nil
    end

    name = string.gsub(name, "^%s+", "")
    name = string.gsub(name, "%s+$", "")
    if name == "" then
        return nil
    end

    return string.lower(name)
end

local function AddAssignmentName(names, name)
    local normalized = NormalizeAssignmentName(name)
    if normalized then
        names[normalized] = true
    end
end

function WQA.Achievements:Register_SPECIAL_ASSIGNMENT(achievement)
    local id = achievement.id

    for _, assignment in ipairs(achievement.criteria or {}) do
        local questIDs = assignment.questIDs or {}
        local candidateNames = {}

        -- Keep the actual world-quest IDs as a fallback once the assignment
        -- has been unlocked. The Area POI path below is what lets us detect
        -- the assignment while it is still locked behind three local WQs.
        for _, questID in ipairs(questIDs) do
            WQA:AddRewardToQuest(questID, "ACHIEVEMENT", id)

            local title = C_QuestLog.GetTitleForQuestID(questID)
            AddAssignmentName(candidateNames, title)

            if C_QuestLog.RequestLoadQuestByID then
                C_QuestLog.RequestLoadQuestByID(questID)
            end
        end

        AddAssignmentName(candidateNames, assignment.name)
        for _, alias in ipairs(assignment.names or {}) do
            AddAssignmentName(candidateNames, alias)
        end

        local mapIDs = assignment.mapIDs or (assignment.mapID and { assignment.mapID }) or {}
        for _, mapID in ipairs(mapIDs) do
            local poiIDs = C_AreaPoiInfo.GetAreaPOIForMap(mapID) or {}
            for _, poiID in ipairs(poiIDs) do
                local poiInfo = C_AreaPoiInfo.GetAreaPOIInfo(mapID, poiID)
                local normalizedPoiName = poiInfo and NormalizeAssignmentName(poiInfo.name)
                if normalizedPoiName and candidateNames[normalizedPoiName] then
                    WQA.Criterias.AreaPoi:AddReward({ AreaPoiId = poiID, MapId = mapID }, "ACHIEVEMENT", id)
                end
            end
        end
    end
end

local function NormalizeEventName(name)
    if type(name) ~= "string" then
        return nil
    end

    name = string.lower(name)
    name = string.gsub(name, "^%s+", "")
    name = string.gsub(name, "%s+$", "")
    -- Progress criteria can be returned as, for example, "5/10 Mysterious Entity".
    name = string.gsub(name, "^%d+/%d+%s+", "")
    return name
end

local function EventNameMatches(name, patterns)
    local normalizedName = NormalizeEventName(name)
    if not normalizedName then
        return false
    end

    for _, pattern in ipairs(patterns or {}) do
        local normalizedPattern = NormalizeEventName(pattern)
        if normalizedPattern and string.find(normalizedName, normalizedPattern, 1, true) then
            return true
        end
    end

    return false
end

local function BuildNormalizedCriterionNames(criterionName)
    local rawNames = type(criterionName) == "table" and criterionName or { criterionName }
    local wantedNames = {}

    for _, rawName in ipairs(rawNames) do
        local normalized = NormalizeEventName(rawName)
        if normalized then
            wantedNames[#wantedNames + 1] = normalized
        end
    end

    return wantedNames
end

local function CriterionNameMatches(normalizedCriteria, wantedNames)
    if not normalizedCriteria then
        return false
    end

    -- Prefer exact matches. The containment fallback is retained for criteria
    -- whose text gains a progress prefix/suffix or minor Blizzard wording change.
    for _, wanted in ipairs(wantedNames) do
        if normalizedCriteria == wanted then
            return true
        end
    end

    for _, wanted in ipairs(wantedNames) do
        if string.find(normalizedCriteria, wanted, 1, true)
            or string.find(wanted, normalizedCriteria, 1, true)
        then
            return true
        end
    end

    return false
end

local function NamedCriterionNeedsProgress(achievementID, criterionName, scanSparseIndexes)
    if not criterionName then
        return nil, false
    end

    local wantedNames = BuildNormalizedCriterionNames(criterionName)
    if #wantedNames == 0 then
        return nil, false
    end

    local numCriteria = tonumber(GetAchievementNumCriteria(achievementID)) or 0
    if numCriteria <= 0 then
        return nil, false
    end

    local maxIndex = numCriteria
    if scanSparseIndexes then
        maxIndex = math.max(32, numCriteria * 8)
    end

    for i = 1, maxIndex do
        local criteriaString, _, completed, quantity, reqQuantity, _, _, _, _, criteriaID =
            SafeGetAchievementCriteriaInfo(achievementID, i)

        if criteriaString ~= nil or criteriaID ~= nil then
            local normalizedCriteria = NormalizeEventName(criteriaString)
            if CriterionNameMatches(normalizedCriteria, wantedNames) then
                return not CriteriaValuesAreComplete(completed, quantity, reqQuantity), true
            end
        end
    end

    return nil, false
end

local STRICT_LOCATION_ACHIEVEMENTS = {
    [61943] = true, -- Abundance: Prosperous Plentitude!
    [62325] = true, -- Abundance: Treasures Aplenty
    [62326] = true, -- Abundance: Golden Opportunities
    [62329] = true, -- Abundance: Squash the Competition
    [62330] = true, -- Abundance: One Bite at a Time
    [62331] = true  -- Abundance: Drops of Prosperity
}

local function IsStrictLocationAchievement(achievement, entry)
    return achievement
        and entry
        and STRICT_LOCATION_ACHIEVEMENTS[achievement.id] == true
        and entry.criterionName ~= nil
end

local function IsReadableTooltipText(value)
    if type(value) ~= "string" then
        return false
    end

    if issecretvalue and issecretvalue(value) then
        return false
    end

    return true
end

local function TooltipTextHasAchievementCheckmark(text)
    if not IsReadableTooltipText(text) then
        return false
    end

    local lower = string.lower(text)
    return string.find(lower, "achievementcompare-yellowcheckmark", 1, true) ~= nil
        or string.find(lower, "achievementcompare-greencheckmark", 1, true) ~= nil
        or string.find(lower, "common-icon-checkmark", 1, true) ~= nil
        or string.find(lower, "checkmark", 1, true) ~= nil
end

local function NormalizeTooltipCriterionText(text)
    if not IsReadableTooltipText(text) then
        return nil
    end

    -- Keep the actual criterion wording, but remove formatting that the
    -- achievement tooltip appends around it. The checkmark itself is inspected
    -- separately from the raw text before this normalization.
    text = string.gsub(text, "|c%x%x%x%x%x%x%x%x", "")
    text = string.gsub(text, "|r", "")
    text = string.gsub(text, "|A:[^|]-|a", "")
    text = string.gsub(text, "|T.-|t", "")
    return NormalizeEventName(text)
end

local function ScanTooltipDataForCriterion(data, wantedNames)
    if type(data) ~= "table" or type(data.lines) ~= "table" then
        return nil, false
    end

    local matchedIncomplete = false

    for _, line in ipairs(data.lines) do
        if type(line) == "table" then
            for _, field in ipairs({ "leftText", "rightText" }) do
                local rawText = line[field]
                local normalizedText = NormalizeTooltipCriterionText(rawText)

                if CriterionNameMatches(normalizedText, wantedNames) then
                    -- This is the exact atlas Blizzard adds to completed criteria
                    -- in the achievement hyperlink tooltip. If any tooltip source
                    -- reports the location checked, completion wins immediately.
                    if TooltipTextHasAchievementCheckmark(rawText) then
                        return false, true
                    end

                    matchedIncomplete = true
                end
            end
        end
    end

    if matchedIncomplete then
        return true, true
    end

    return nil, false
end

local function TooltipCriterionNeedsProgress(achievementID, criterionName)
    if not criterionName or not C_TooltipInfo then
        return nil, false
    end

    local wantedNames = BuildNormalizedCriterionNames(criterionName)
    if #wantedNames == 0 then
        return nil, false
    end

    local matchedIncomplete = false

    -- First use the same hyperlink tooltip that the player sees when hovering
    -- the achievement in WQAW. This avoids interpreting criteria indexes,
    -- criteria-tree parents, asset IDs, or achievement-link bit masks ourselves.
    if C_TooltipInfo.GetHyperlink then
        local link = GetAchievementLink(achievementID)
        if IsReadableTooltipText(link) then
            local ok, data = pcall(C_TooltipInfo.GetHyperlink, link)
            if ok and data then
                local needsProgress, matched = ScanTooltipDataForCriterion(data, wantedNames)
                if matched and not needsProgress then
                    return false, true
                elseif matched then
                    matchedIncomplete = true
                end
            end
        end
    end

    -- GetAchievementByID is a useful second representation of the same
    -- Blizzard tooltip data and does not depend on the link string being cached.
    if C_TooltipInfo.GetAchievementByID then
        local ok, data = pcall(C_TooltipInfo.GetAchievementByID, achievementID)
        if ok and data then
            local needsProgress, matched = ScanTooltipDataForCriterion(data, wantedNames)
            if matched and not needsProgress then
                return false, true
            elseif matched then
                matchedIncomplete = true
            end
        end
    end

    if matchedIncomplete then
        return true, true
    end

    return nil, false
end

function WQA.Achievements:RotatingEventEntryNeedsProgress(achievement, entry)
    if not achievement or not entry then
        return false, false
    end

    local strictPerLocation = IsStrictLocationAchievement(achievement, entry)

    if strictPerLocation then
        -- The tooltip is the authoritative source for Abundance. It is the same
        -- data path that visibly produces the yellow checkmarks in the user's
        -- achievement tooltip, so there is no index/asset mapping to guess.
        local needsProgress, matched =
            TooltipCriterionNeedsProgress(achievement.id, entry.criterionName)

        if matched then
            return needsProgress, true
        end

        -- If tooltip data is temporarily unavailable, do not show a possibly
        -- completed Abundance criterion. A later refresh can safely add it.
        WQA:Debug(
            "Strict rotating-event tooltip criterion unavailable",
            achievement.id,
            entry.mapID,
            entry.criterionName and tostring(entry.criterionName) or "nil"
        )
        return false, false
    end

    local needsProgress, matched =
        NamedCriterionNeedsProgress(achievement.id, entry.criterionName, false)

    if matched then
        return needsProgress, true
    end

    -- Legacy rotating-event entries keep their previous useful-side fallback.
    return true, true
end

local function EntryContainsMap(entry, mapID)
    if not entry or not mapID then
        return false
    end

    if entry.mapID == mapID then
        return true
    end

    for _, candidateMapID in ipairs(entry.mapIDs or {}) do
        if candidateMapID == mapID then
            return true
        end
    end

    return false
end

function WQA.Achievements:GetRotatingEventEntryForMap(achievementID, mapID)
    for expansionID = 7, 12 do
        local data = WQA.data[expansionID]
        if data and type(data.achievements) == "table" then
            for _, achievement in pairs(data.achievements) do
                if achievement.id == achievementID
                    and achievement.criteriaType == "ROTATING_EVENT"
                then
                    for _, entry in ipairs(achievement.criteria or {}) do
                        if EntryContainsMap(entry, mapID) then
                            return achievement, entry
                        end
                    end
                end
            end
        end
    end

    return nil, nil
end

function WQA.Achievements:ShouldKeepCachedRotatingAchievement(achievementID, mapID)
    local achievement, entry =
        self:GetRotatingEventEntryForMap(achievementID, mapID)

    -- nil means this is not one of the strict per-location rotating rewards.
    -- Leave legacy/non-Abundance cached rewards untouched.
    if not achievement or not entry then
        return nil
    end

    -- Only strict per-location Abundance rewards are revalidated here.
    -- Other rotating events retain the existing cache behavior.
    if not IsStrictLocationAchievement(achievement, entry) then
        return nil
    end

    local needsProgress, matched =
        self:RotatingEventEntryNeedsProgress(achievement, entry)

    if not matched then
        return false
    end

    return needsProgress == true
end

function WQA.Achievements:PruneCompletedRotatingAchievementRewards(achievementRewards, mapID)
    if type(achievementRewards) ~= "table" then
        return false
    end

    local changed = false

    for index = #achievementRewards, 1, -1 do
        local reward = achievementRewards[index]
        local keep = reward
            and reward.id
            and self:ShouldKeepCachedRotatingAchievement(reward.id, mapID)
            or nil

        if keep == false then
            WQA:Debug(
                "Removing completed rotating achievement reward",
                reward and reward.id,
                mapID
            )
            table.remove(achievementRewards, index)
            changed = true
        end
    end

    return changed
end

local function AddRotatingEventMatches(entry, achievementID)
    local mapIDs = entry.mapIDs or (entry.mapID and { entry.mapID }) or {}
    local patterns = entry.patterns or entry.names or {}

    for _, mapID in ipairs(mapIDs) do
        -- Some Midnight events are Area POIs rather than ordinary task quests.
        for _, poiID in ipairs(C_AreaPoiInfo.GetAreaPOIForMap(mapID) or {}) do
            local poiInfo = C_AreaPoiInfo.GetAreaPOIInfo(mapID, poiID)
            if poiInfo and EventNameMatches(poiInfo.name, patterns) then
                WQA.Criterias.AreaPoi:AddReward({ AreaPoiId = poiID, MapId = mapID }, "ACHIEVEMENT", achievementID)
            end
        end

        -- Void Strikes and similar open-world objectives can also be exposed as
        -- task quests. Track either representation so Blizzard can change the
        -- map pin implementation without breaking WorldQuestAchievementWatcher again.
        for _, questInfo in ipairs(C_TaskQuest.GetQuestsOnMap(mapID) or {}) do
            local questID = questInfo.questId or questInfo.questID
            if questID then
                local title = C_TaskQuest.GetQuestInfoByQuestID(questID) or C_QuestLog.GetTitleForQuestID(questID)
                if EventNameMatches(title, patterns) then
                    WQA:AddRewardToQuest(questID, "ACHIEVEMENT", achievementID)
                end
            end
        end

        -- Midnight 12.1's Events tab uses C_EventScheduler for activities such
        -- as Cursed Surges. These may not appear in GetAreaPOIForMap() at all,
        -- even while the event is currently active.
        for _, scheduledEvent in ipairs(WQA.eventSchedulerOngoing or {}) do
            if scheduledEvent.mapID == mapID and EventNameMatches(scheduledEvent.name, patterns) then
                WQA.Criterias.AreaPoi:AddReward({
                    AreaPoiId = scheduledEvent.areaPoiID,
                    MapId = mapID,
                    Name = scheduledEvent.name,
                    EventScheduler = true
                }, "ACHIEVEMENT", achievementID)
            end
        end

        -- Once some public events actually begin, Blizzard can expose them as
        -- outdoor scenarios instead of Area POIs/tasks/scheduler entries. The
        -- Cursed Surges on 12.1.0 can report, for example, scenario
        -- "The Broodmother's Nest" with step "Cull the Brood". Match the
        -- scenario name against the same rotation aliases and register a
        -- synthetic Area POI so all existing display/filtering code is reused.
        local scenarioEvent = WQA:GetActiveScenarioEvent()
        if scenarioEvent and EventNameMatches(scenarioEvent.name, patterns) then
            WQA.Criterias.AreaPoi:AddReward({
                AreaPoiId = scenarioEvent.areaPoiID,
                MapId = mapID,
                Name = scenarioEvent.name,
                ScenarioEvent = true,
                ScenarioID = scenarioEvent.scenarioID
            }, "ACHIEVEMENT", achievementID)
        end
    end
end

function WQA.Achievements:Register_ROTATING_EVENT(achievement)
    for _, entry in ipairs(achievement.criteria or {}) do
        local needsProgress =
            self:RotatingEventEntryNeedsProgress(achievement, entry)

        if needsProgress then
            AddRotatingEventMatches(entry, achievement.id)
        end
    end
end

function WQA.Achievements:Register_QUEST_SINGLE(achievement)
    local id = achievement.id

    if type(achievement.criteria) == "table" then
        for _, questID in pairs(achievement.criteria) do
            WQA:AddRewardToQuest(questID, "ACHIEVEMENT", id)
        end
    else
        WQA:AddRewardToQuest(achievement.criteria, "ACHIEVEMENT", id)
    end
end

function WQA.Achievements:Register_QUEST_PIN(achievement, forced)
    local id = achievement.id

    C_QuestLine.RequestQuestLinesForMap(achievement.mapID)
    for i = 1, GetAchievementNumCriteria(id) do
        local _, _, _, _, _, _, _, questID = GetAchievementCriteriaInfo(id, i)
        local completed = IsAchievementCriteriaComplete(id, i)

        if not questID then
            return
        end

        if not completed or forced then
            if achievement.criteriaInfo[i] then
                for _, questID in pairs(achievement.criteriaInfo[i]) do
                    WQA:AddRewardToQuest(questID, "ACHIEVEMENT", id)
                    WQA.questPinMapList[achievement.mapID] = true
                    WQA.questPinList[questID] = true
                end
            else
                WQA:AddRewardToQuest(questID, "ACHIEVEMENT", id)
                WQA.questPinMapList[achievement.mapID] = true
                WQA.questPinList[questID] = true
            end
        end
    end
end

function WQA.Achievements:Register_QUEST_FLAG(achievement)
    WQA:AddRewardToQuest(achievement.criteria, "ACHIEVEMENT", achievement.id)
    WQA.questFlagList[achievement.criteria] = true
end

local function RegisterQuestCriteriaGroup(achievement, criteria)
    local id = achievement.id

    if type(criteria) == "table" then
        for _, questID in pairs(criteria) do
            WQA:AddRewardToQuest(questID, "ACHIEVEMENT", id)
        end
    elseif criteria then
        WQA:AddRewardToQuest(criteria, "ACHIEVEMENT", id)
    end
end

function WQA.Achievements:Register_QUESTS(achievement, index, criteriaQuestId)
    -- Prefer Blizzard's live criteria assetID (quest ID) over positional
    -- indexing. Achievement criteria are not guaranteed to be returned in
    -- the same order as our data table. Matching by quest ID prevents a
    -- completed criterion from registering a different quest at the same
    -- numeric index.
    if criteriaQuestId then
        for _, configuredCriteria in pairs(achievement.criteria or {}) do
            if type(configuredCriteria) == "table" then
                for _, configuredQuestId in pairs(configuredCriteria) do
                    if configuredQuestId == criteriaQuestId then
                        RegisterQuestCriteriaGroup(achievement, configuredCriteria)
                        return
                    end
                end
            elseif configuredCriteria == criteriaQuestId then
                RegisterQuestCriteriaGroup(achievement, configuredCriteria)
                return
            end
        end
    end

    -- Older achievements sometimes need a hand-maintained mapping or use
    -- alternate quest IDs that Blizzard does not expose directly. Preserve
    -- the original index-based behavior as a compatibility fallback.
    RegisterQuestCriteriaGroup(achievement, achievement.criteria and achievement.criteria[index])
end

function WQA.Achievements:Register_MISSION_TABLE(achievement, index, criteriaQuestId)
    local id = achievement.id

    if achievement.criteria and achievement.criteria[index] then
        if type(achievement.criteria[index]) == "table" then
            for _, questID in pairs(achievement.criteria[index]) do
                WQA:AddRewardToMission(questID, "ACHIEVEMENT", id)
            end
        else
            local questID = achievement.criteria[index]
            if questID then
                WQA:AddRewardToMission(questID, "ACHIEVEMENT", id)
            end
        end
    else
        WQA:AddRewardToMission(criteriaQuestId, "ACHIEVEMENT", id)
    end
end

function WQA.Achievements:Register_AREA_POI(achievement, index)
    local id = achievement.id

    if not achievement.criteria[index].AreaPoiId then
        for _, areaPoi in pairs(achievement.criteria[index]) do
            WQA.Criterias.AreaPoi:AddReward(areaPoi, "ACHIEVEMENT", id)
        end
    else
        local areaPoi = achievement.criteria[index]
        if areaPoi then
            WQA.Criterias.AreaPoi:AddReward(areaPoi, "ACHIEVEMENT", id)
        end
    end
end
