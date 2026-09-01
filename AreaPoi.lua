---@class WorldQuestAchievementWatcher
local WQA = WorldQuestAchievementWatcher

---@alias AreaPoiCriteria
---| { AreaPoiId: integer, MapId: integer}

local criteria = {}
criteria.list = {}
criteria.watched = {}

---@param poi AreaPoiCriteria
---@param rewardType RewardType
---@param emissary boolean?
function criteria:AddReward(poi, rewardType, reward, emissary)
    -- Historical data in this addon used both AreaPoiId and AreaPoiID.
    -- Accept both spellings so old data and new dynamic Midnight POIs work.
    local poiId = poi.AreaPoiId or poi.AreaPoiID
    local mapId = poi.MapId or poi.mapID

    if not poiId or not mapId then
        return
    end

    if not self.list[poiId] then
        self.list[poiId] = {}
    end
    if not self.list[poiId][mapId] then
        self.list[poiId][mapId] = {}
    end

    local l = self.list[poiId][mapId]
    if poi.Name and not l.name then
        l.name = poi.Name
    end
    if poi.EventScheduler then
        l.eventScheduler = true
    end
    if poi.ScenarioEvent then
        l.scenarioEvent = true
        l.scenarioID = poi.ScenarioID
    end

    WQA:AddReward(l, rewardType, reward, emissary)
end

local AREA_POI_CONSISTENCY_RETRY_LIMIT = 3

function criteria:Check()
    local active = {}
    local new = {}
    local retry = false
    local now = GetServerTime and GetServerTime() or time()

    -- The Event Scheduler cache itself can be transient. Refresh it again on
    -- later validation passes while an explicit full refresh is checking a
    -- previously active event.
    if WQA.fullRefreshExplicitlyRequested then
        WQA.areaPoiConsistencyCheckPass = (WQA.areaPoiConsistencyCheckPass or 0) + 1
        if WQA.areaPoiConsistencyCheckPass > 1
            and C_EventScheduler
            and C_EventScheduler.GetOngoingEvents
            and (not C_EventScheduler.HasData or C_EventScheduler.HasData())
        then
            WQA:RefreshEventSchedulerCache()
        end
    end

    for poiId, mapIds in pairs(self.list) do
        for mapId in pairs(mapIds) do
            local entry = self.list[poiId][mapId]
            local poiInfo = C_AreaPoiInfo.GetAreaPOIInfo(mapId, poiId)
            local schedulerInfo = entry.eventScheduler and WQA:GetScheduledAreaPoiInfo(poiId, mapId) or nil
            local scenarioInfo = entry.scenarioEvent and WQA:GetScenarioAreaPoiInfo(poiId, mapId) or nil
            local isActive = poiInfo or schedulerInfo or scenarioInfo
            local key = WQA:GetAreaPoiConsistencyKey(poiId, mapId)
            local expectedUntil =
                (WQA.areaPoiExpectedActive and WQA.areaPoiExpectedActive[key])
                or entry._wqawExpectedUntil

            if isActive then
                local expiresAt = WQA:GetAreaPoiExpiration(poiId, schedulerInfo, entry)
                if expiresAt then
                    entry.expiresAt = expiresAt
                elseif type(entry.expiresAt) == "number" and entry.expiresAt <= now then
                    entry.expiresAt = nil
                end

                entry._wqawConsistencyFallback = nil
                entry._wqawExpectedUntil = nil

                if WQA.areaPoiUnresolved then
                    WQA.areaPoiUnresolved[key] = nil
                end

                local link
                for k, v in pairs(entry.reward) do
                    if k == "custom" or k == "professionSkillup" or k == "gold" then
                        link = true
                    else
                        link = WQA:GetRewardLinkByID(poiId, k, v, 1)
                    end

                    if not link then
                        -- Retail can leave achievement/item links uncached. The
                        -- live POI is still authoritative, so do not suppress a
                        -- rotating event just because its reward link is late.
                        WQA:Debug(poiId, k, v, 1)
                    else
                        WQA:SetRewardLinkByID(poiId, k, v, 1, link)
                    end

                    if k == "achievement" or k == "chance" or k == "azeriteTraits" then
                        for i = 2, #v do
                            link = WQA:GetRewardLinkByID(poiId, k, v, i)
                            if not link then
                                WQA:Debug(poiId, k, v, i)
                            else
                                WQA:SetRewardLinkByID(poiId, k, v, i, link)
                            end
                        end
                    end
                end
                if not link then
                    WQA:Debug(poiId, (poiInfo and poiInfo.name) or entry.name or (schedulerInfo and schedulerInfo.name) or (scenarioInfo and scenarioInfo.name), link)
                end

                if not active[poiId] then
                    active[poiId] = {}
                end
                active[poiId][mapId] = true

                if not self.watched[poiId] or not self.watched[poiId][mapId] then
                    if not new[poiId] then
                        new[poiId] = {}
                    end
                    new[poiId][mapId] = true
                end
            elseif
                WQA.fullRefreshExplicitlyRequested
                and type(expectedUntil) == "number"
                and expectedUntil > now
            then
                WQA.areaPoiConsistencyRetryCounts = WQA.areaPoiConsistencyRetryCounts or {}
                WQA.areaPoiUnresolved = WQA.areaPoiUnresolved or {}

                local attempts = (WQA.areaPoiConsistencyRetryCounts[key] or 0) + 1
                WQA.areaPoiConsistencyRetryCounts[key] = attempts
                WQA.areaPoiConsistencyRetries = (WQA.areaPoiConsistencyRetries or 0) + 1

                WQA:Debug(
                    "Retrying previously active Area POI",
                    poiId,
                    mapId,
                    "attempt=" .. tostring(attempts),
                    "expectedUntil=" .. tostring(expectedUntil)
                )

                -- Keep CheckWQ in its non-committing retry path. After the final
                -- attempt mark the snapshot unresolved; the next CheckWQ pass
                -- will reject the entire full refresh and restore the prior list.
                retry = true
                if attempts >= AREA_POI_CONSISTENCY_RETRY_LIMIT then
                    WQA.areaPoiUnresolved[key] = true
                    WQA:Debug("Area POI still missing after retries", poiId, mapId)
                end
            else
                -- The cached timer ended (or there was never positive evidence
                -- that this POI should still be active), so disappearance is
                -- allowed to represent a legitimate event rotation.
                entry._wqawConsistencyFallback = nil
                entry._wqawExpectedUntil = nil
                if WQA.areaPoiUnresolved then
                    WQA.areaPoiUnresolved[key] = nil
                end
            end
        end
    end

    return {
        active = active,
        new = new,
        retry = retry
    }
end

WQA.Criterias.AreaPoi = criteria
