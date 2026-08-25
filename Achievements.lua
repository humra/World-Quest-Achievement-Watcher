local WQA = WorldQuestAchievementWatcher

WQA.Achievements = {}

local function IsAchievementCriteriaComplete(achievementID, criteriaIndex)
    local _, _, completed, quantity, reqQuantity = GetAchievementCriteriaInfo(achievementID, criteriaIndex)

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

local function NamedCriterionNeedsProgress(achievementID, criterionName)
    if not criterionName then
        return true
    end

    local rawNames = type(criterionName) == "table" and criterionName or { criterionName }
    local wantedNames = {}
    for _, rawName in ipairs(rawNames) do
        local normalized = NormalizeEventName(rawName)
        if normalized then
            wantedNames[#wantedNames + 1] = normalized
        end
    end

    if #wantedNames == 0 then
        return true
    end

    for i = 1, GetAchievementNumCriteria(achievementID) do
        local criteriaString = GetAchievementCriteriaInfo(achievementID, i)
        local normalizedCriteria = NormalizeEventName(criteriaString)
        if normalizedCriteria then
            for _, wanted in ipairs(wantedNames) do
                if string.find(normalizedCriteria, wanted, 1, true) or string.find(wanted, normalizedCriteria, 1, true) then
                    return not IsAchievementCriteriaComplete(achievementID, i)
                end
            end
        end
    end

    -- If Blizzard localizes or hides the criterion name differently, err on the
    -- useful side and allow the active event to be shown rather than silently
    -- missing a rare rotation.
    return true
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
        if NamedCriterionNeedsProgress(achievement.id, entry.criterionName) then
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
