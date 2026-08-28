---@class WorldQuestAchievementWatcher
local WQA = WorldQuestAchievementWatcher

local L = WQA.L
local LibQTip = LibStub("LibQTip-1.0")

-- Retail 12.x secret values can taint Blizzard's tooltip widget manager even
-- through addon-created GameTooltipTemplate frames. WQAW therefore uses a
-- plain LibQTip panel for popup hover details and reads hyperlink tooltip data
-- without creating or modifying any Blizzard GameTooltip frame.
local HOVER_TOOLTIP_KEY = "WorldQuestAchievementWatcherHoverQTip"
local wqawHoverTooltip

local function ReleaseHoverTooltip()
    if wqawHoverTooltip then
        LibQTip:Release(wqawHoverTooltip)
        wqawHoverTooltip = nil
    end
end

local function AcquireHoverTooltip(owner)
    ReleaseHoverTooltip()

    local tooltip = LibQTip:Acquire(HOVER_TOOLTIP_KEY, 1, "LEFT")
    wqawHoverTooltip = tooltip

    tooltip:ClearAllPoints()
    tooltip:SetPoint("BOTTOMLEFT", owner, "TOPLEFT", 0, 2)
    tooltip:SetFrameStrata("TOOLTIP")
    tooltip:SetClampedToScreen(true)

    return tooltip
end

local function IsSafeTooltipValue(value)
    if value == nil then
        return false
    end

    if issecretvalue and issecretvalue(value) then
        return false
    end

    return true
end

local function AddHoverLine(tooltip, text)
    if not IsSafeTooltipValue(text) then
        return
    end

    tooltip:AddLine(text)
end

local function AddHyperlinkHoverData(tooltip, link)
    if
        not link
        or not C_TooltipInfo
        or not C_TooltipInfo.GetHyperlink
    then
        return false
    end

    local ok, data = pcall(C_TooltipInfo.GetHyperlink, link)
    if
        not ok
        or not data
        or type(data.lines) ~= "table"
    then
        return false
    end

    local added = false

    for _, lineData in ipairs(data.lines) do
        local leftText =
            IsSafeTooltipValue(lineData.leftText) and lineData.leftText or nil
        local rightText =
            IsSafeTooltipValue(lineData.rightText) and lineData.rightText or nil

        if leftText and rightText then
            tooltip:AddLine(leftText .. "    " .. rightText)
            added = true
        elseif leftText then
            tooltip:AddLine(leftText)
            added = true
        elseif rightText then
            tooltip:AddLine(rightText)
            added = true
        end
    end

    return added
end
function WQA:CreateQTip()
    if not LibQTip:IsAcquired("WorldQuestAchievementWatcher") and not self.tooltip then
        local tooltip = LibQTip:Acquire("WorldQuestAchievementWatcher", 2, "LEFT", "LEFT")
        self.tooltip = tooltip

        tooltip:SetScript("OnHide", function()
            if WQA.PopUp then
                WQA.PopUp:Hide()
            end
        end)

        if self.db.profile.options.popupShowExpansion or self.db.profile.options.popupShowZone then
            tooltip:AddColumn()
        end
        if self.db.profile.options.popupShowTime then
            tooltip:AddColumn()
        end

        tooltip:AddHeader(_G.WORLD_QUEST_BANNER)
        tooltip:SetCell(1, tooltip:GetColumnCount(), _G.REWARDS)
        tooltip:SetFrameStrata("MEDIUM")
        tooltip:SetFrameLevel(100)
        tooltip:AddSeparator()
    end
end

---@param questID number
local function GetIconTexture(questID)
    local texture = select(2, GetQuestLogRewardInfo(1, questID))
    if texture then
        return texture
    end

    local currencyInfo = C_QuestLog.GetQuestRewardCurrencyInfo(questID, 1, false)
    if currencyInfo then
        return currencyInfo.texture
    end

    return [[Interface\GossipFrame\auctioneerGossipIcon]]
end

function WQA:UpdateQTip(tasks)
    local tooltip = self.tooltip
    if next(tasks) == nil then
        tooltip:AddLine(L["NO_QUESTS"])
    else
        tooltip.quests = tooltip.quests or {}
        tooltip.missions = tooltip.missions or {}
        tooltip.pois = tooltip.pois or {}

        local i = tooltip:GetLineCount()
        local expansion, zoneID
        for _, task in ipairs(tasks) do
            local id = task.id
            local poiKey = task.type == "AREA_POI" and (tostring(task.mapId) .. ":" .. tostring(id)) or nil
            if
                (task.type == "WORLD_QUEST" and not tooltip.quests[id]) or (task.type == "MISSION" and not tooltip.missions[id]) or
                (task.type == "AREA_POI" and not tooltip.pois[poiKey])
            then
                local j = 1

                if self.db.profile.options.popupShowExpansion then
                    j = 2
                    if self:GetExpansion(task) ~= expansion then
                        expansion = self:GetExpansion(task)
                        tooltip:AddLine(string.format("|cff33ff33%s|r", self:GetExpansionName(expansion)))
                        i = i + 1
                        zoneID = nil
                    end
                end

                tooltip:AddLine()
                i = i + 1

                if self.db.profile.options.popupShowZone then
                    j = 2
                    if self:GetTaskZoneID(task) ~= zoneID then
                        zoneID = self:GetTaskZoneID(task)
                        tooltip:SetCell(i, 1, "     " .. self:GetTaskZoneName(task))
                    end
                end

                if self.db.profile.options.popupShowTime then
                    local taskTime = self:GetTaskTime(task)
                    if taskTime and taskTime > 0 then
                        tooltip:SetCell(i, j, self:formatTime(taskTime))
                    end
                    j = j + 1
                end

                if task.type == "WORLD_QUEST" then
                    tooltip.quests[id] = true
                elseif task.type == "MISSION" then
                    tooltip.missions[id] = true
                elseif task.type == "AREA_POI" then
                    tooltip.pois[poiKey] = true
                end

                local link = self:GetTaskLink(task)
                tooltip:SetCell(i, j, link)

                tooltip:SetCellScript(
                    i,
                    j,
                    "OnEnter",
                    function(self)
                        local hoverTooltip = AcquireHoverTooltip(self)

                        if task.type == "WORLD_QUEST" then
                            if not AddHyperlinkHoverData(hoverTooltip, link) then
                                AddHoverLine(hoverTooltip, link)
                            end
                        elseif task.type == "MISSION" then
                            AddHoverLine(
                                hoverTooltip,
                                C_Garrison.GetMissionName(id)
                            )
                            AddHoverLine(
                                hoverTooltip,
                                string.format(
                                    GARRISON_MISSION_TOOLTIP_NUM_REQUIRED_FOLLOWERS,
                                    C_Garrison.GetMissionMaxFollowers(id)
                                )
                            )
                            AddHoverLine(
                                hoverTooltip,
                                GARRISON_MISSION_AVAILABILITY
                            )
                            AddHoverLine(
                                hoverTooltip,
                                WQA.missionList[task.id].offerTimeRemaining
                            )

                            if
                                not C_Garrison.IsPlayerInGarrison(
                                    WQA.missionList[task.id].followerType
                                )
                            then
                                AddHoverLine(
                                    hoverTooltip,
                                    GarrisonFollowerOptions[
                                        WQA.missionList[task.id].followerType
                                    ].strings.RETURN_TO_START
                                )
                            end
                        elseif task.type == "AREA_POI" then
                            local poiInfo =
                                C_AreaPoiInfo.GetAreaPOIInfo(
                                    task.mapId,
                                    task.id
                                )
                            local schedulerInfo =
                                WQA:GetScheduledAreaPoiInfo(
                                    task.id,
                                    task.mapId
                                )
                            local scenarioInfo =
                                WQA:GetScenarioAreaPoiInfo(
                                    task.id,
                                    task.mapId
                                )
                            local fallbackEntry =
                                WQA.Criterias.AreaPoi.list[task.id]
                                and WQA.Criterias.AreaPoi.list[task.id][task.mapId]

                            local displayName =
                                (poiInfo and poiInfo.name)
                                or (schedulerInfo and schedulerInfo.name)
                                or (scenarioInfo and scenarioInfo.name)
                                or (fallbackEntry and fallbackEntry.name)

                            if not displayName then
                                ReleaseHoverTooltip()
                                return
                            end

                            AddHoverLine(hoverTooltip, displayName)

                            if poiInfo and poiInfo.description then
                                AddHoverLine(
                                    hoverTooltip,
                                    poiInfo.description
                                )
                            end

                            local tooltipSecondsLeft

                            if
                                poiInfo
                                and C_AreaPoiInfo.IsAreaPOITimed(
                                    poiInfo.areaPoiID
                                )
                            then
                                tooltipSecondsLeft =
                                    C_AreaPoiInfo.GetAreaPOISecondsLeft(
                                        poiInfo.areaPoiID
                                    )
                            elseif
                                schedulerInfo
                                and schedulerInfo.endTime
                            then
                                local now =
                                    GetServerTime and GetServerTime() or time()
                                tooltipSecondsLeft =
                                    schedulerInfo.endTime - now
                            end

                            if
                                IsSafeTooltipValue(tooltipSecondsLeft)
                                and type(tooltipSecondsLeft) == "number"
                                and tooltipSecondsLeft > 0
                            then
                                AddHoverLine(
                                    hoverTooltip,
                                    BONUS_OBJECTIVE_TIME_LEFT:format(
                                        SecondsToTime(tooltipSecondsLeft)
                                    )
                                )
                            end
                        end

                        hoverTooltip:Show()
                    end
                )
                tooltip:SetCellScript(
                    i,
                    j,
                    "OnLeave",
                    function()
                        ReleaseHoverTooltip()
                    end
                )                tooltip:SetCellScript(
                    i,
                    j,
                    "OnMouseDown",
                    function()
                        if ChatEdit_TryInsertChatLink(link) ~= true then
                            if
                                task.type == "WORLD_QUEST" and not WQA.questList[id].isEmissary and
                                not (self.questPinList[id] or self.questFlagList[id])
                            then
                                if WorldQuestTrackerAddon and self.db.profile.options.WorldQuestTracker then
                                    if WorldQuestTrackerAddon.IsQuestBeingTracked(id) then
                                        WorldQuestTrackerAddon.RemoveQuestFromTracker(id)
                                        WQA:ScheduleTimer(
                                            function()
                                                WorldQuestTrackerAddon:FullTrackerUpdate()
                                            end,
                                            .5
                                        )
                                    else
                                        local _, _, numObjectives = GetTaskInfo(id)
                                        local widget = {
                                            questID = id,
                                            mapID = self:GetQuestZoneID(id),
                                            numObjectives = numObjectives
                                        }
                                        zoneID = self:GetQuestZoneID(id)
                                        local x, y = C_TaskQuest.GetQuestLocation(id, zoneID)
                                        widget.questX, widget.questY = x or 0, y or 0
                                        widget.IconTexture = GetIconTexture(id)
                                        local function f(widget)
                                            if not widget.IconTexture then
                                                WQA:ScheduleTimer(
                                                    function()
                                                        widget.IconTexture = GetIconTexture(id)
                                                        f(widget)
                                                    end,
                                                    1.5
                                                )
                                            else
                                                WorldQuestTrackerAddon.AddQuestToTracker(widget)
                                                WQA:ScheduleTimer(
                                                    function()
                                                        WorldQuestTrackerAddon:FullTrackerUpdate()
                                                    end,
                                                    .5
                                                )
                                            end
                                        end
                                        f(widget)
                                    end
                                else
                                    if not C_QuestLog.AddWorldQuestWatch(id, 1) then
                                        C_QuestLog.RemoveWorldQuestWatch(id)
                                    end
                                end
                            end
                        end
                    end
                )

                local list
                if task.type == "WORLD_QUEST" then
                    list = WQA.questList[id].reward
                elseif task.type == "MISSION" then
                    list = WQA.missionList[id].reward
                elseif task.type == "AREA_POI" then
                    list = WQA.Criterias.AreaPoi.list[task.id][task.mapId].reward
                end

                local more = false
                for k, v in pairs(list) do
                    for n = 1, 3 do
                        if n == 1 or (n > 1 and (k == "achievement" or k == "chance" or k == "azeriteTraits")) then
                            local text = self:GetRewardTextByID(id, k, v, n, task.type)
                            if text then
                                j = j + 1

                                if j > tooltip:GetColumnCount() then
                                    tooltip:AddColumn()
                                end
                                tooltip:SetCell(i, j, text)

                                tooltip:SetCellScript(
                                    i,
                                    j,
                                    "OnEnter",
                                    function(self)
                                        local hoverTooltip =
                                            AcquireHoverTooltip(self)
                                        local rewardLink =
                                            WQA:GetRewardLinkByID(
                                                id,
                                                k,
                                                v,
                                                n
                                            )

                                        if rewardLink then
                                            if
                                                not AddHyperlinkHoverData(
                                                    hoverTooltip,
                                                    rewardLink
                                                )
                                            then
                                                AddHoverLine(
                                                    hoverTooltip,
                                                    rewardLink
                                                )
                                            end
                                        else
                                            AddHoverLine(
                                                hoverTooltip,
                                                WQA:GetRewardTextByID(
                                                    id,
                                                    k,
                                                    v,
                                                    n,
                                                    task.type
                                                )
                                            )
                                        end

                                        hoverTooltip:Show()
                                    end
                                )
                                tooltip:SetCellScript(
                                    i,
                                    j,
                                    "OnLeave",
                                    function()
                                        ReleaseHoverTooltip()
                                        ResetCursor()
                                    end
                                )                                -- Capture the achievement ID for this specific reward cell.
                                -- This avoids relying on the surrounding loop variables later
                                -- when the user actually clicks the cell.
                                local achievementID =
                                    k == "achievement" and v[n] and v[n].id or nil

                                tooltip:SetCellScript(
                                    i,
                                    j,
                                    "OnMouseDown",
                                    function(_, _, button)
                                        local rewardLink = WQA:GetRewardLinkByID(id, k, v, n)

                                        if
                                            achievementID
                                            and button == "LeftButton"
                                            and not IsShiftKeyDown()
                                            and not IsControlKeyDown()
                                            and not IsAltKeyDown()
                                        then
                                            ShowAchievementFrameForAchievement(achievementID)
                                        elseif rewardLink then
                                            HandleModifiedItemClick(rewardLink)
                                        end
                                    end
                                )
                                if n == 3 then
                                    local m = 4
                                    if self:GetRewardTextByID(id, k, v, m, task.type) then
                                        j = j + 1
                                        if j > tooltip:GetColumnCount() then
                                            tooltip:AddColumn()
                                        end
                                        tooltip:SetCell(i, j, "...")
                                        local moreTooltipText = ""
                                        while self:GetRewardTextByID(id, k, v, m, task.type) do
                                            if m == 4 then
                                                moreTooltipText = moreTooltipText ..
                                                    self:GetRewardTextByID(id, k, v, m, task.type)
                                            else
                                                moreTooltipText = moreTooltipText ..
                                                    "\n" .. self:GetRewardTextByID(id, k, v, m, task.type)
                                            end
                                            m = m + 1
                                        end

                                        tooltip:SetCellScript(
                                            i,
                                            j,
                                            "OnEnter",
                                            function(self)
                                                local hoverTooltip =
                                                    AcquireHoverTooltip(self)

                                                for lineText in string.gmatch(
                                                    moreTooltipText,
                                                    "[^\n]+"
                                                ) do
                                                    AddHoverLine(
                                                        hoverTooltip,
                                                        lineText
                                                    )
                                                end

                                                hoverTooltip:Show()
                                            end
                                        )
                                        tooltip:SetCellScript(
                                            i,
                                            j,
                                            "OnLeave",
                                            function()
                                                ReleaseHoverTooltip()
                                            end
                                        )                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    tooltip:Show()
end

function WQA:AnnouncePopUp(quests, silent)
    if not self.PopUp then
        local PopUp = CreateFrame("Frame", "WorldQuestAchievementWatcherPopUp", UIParent, "UIPanelDialogTemplate")
        if self.db.profile.options.esc then
            tinsert(UISpecialFrames, "WorldQuestAchievementWatcherPopUp")
        end
        self.PopUp = PopUp
        PopUp:SetMovable(true)
        PopUp:EnableMouse(true)
        PopUp:RegisterForDrag("LeftButton")
        PopUp:SetScript(
            "OnDragStart",
            function(self)
                self.moving = true
                self:StartMoving()
            end
        )
        PopUp:SetScript(
            "OnDragStop",
            function(self)
                self.moving = nil
                self:StopMovingOrSizing()
                if WQA.db.profile.options.popupRememberPosition then
                    WQA.db.profile.options.popupX = self:GetLeft()
                    WQA.db.profile.options.popupY = self:GetTop()
                end
            end
        )
        PopUp:SetWidth(300)
        PopUp:SetHeight(100)
        PopUp:SetPoint("CENTER") --, self.db.profile.options.popupX, self.db.profile.options.popupY)
        --PopUp:SetPoint("TOPLEFT", self.db.profile.options.popupX, self.db.profile.options.popupY)
        PopUp:Hide()

        PopUp:SetScript(
            "OnHide",
            function()
                ReleaseHoverTooltip()

                if WQA.tooltip ~= nil then
                    LibQTip:Release(WQA.tooltip)
                    WQA.tooltip.quests = nil
                    WQA.tooltip.missions = nil
                    WQA.tooltip.pois = nil
                    WQA.tooltip = nil
                end

                PopUp.shown = false
                WQA.popupRequestActive = false
            end
        )
    end
    if next(quests) == nil and silent == true then
        return
    end
    local PopUp = self.PopUp
    PopUp:Show()
    PopUp.shown = true
    self:CreateQTip()
    self.tooltip:SetAutoHideDelay()
    self.tooltip:ClearAllPoints()
    self.tooltip:SetPoint("TOP", PopUp, "TOP", 2, -27)
    self:UpdateQTip(quests)
    PopUp:SetWidth(self.tooltip:GetWidth() + 8.5)
    PopUp:SetHeight(self.tooltip:GetHeight() + 32)
    PopUp:SetScale(self.tooltip:GetScale())
    if (PopUp:GetEffectiveScale() ~= self.tooltip:GetEffectiveScale()) then
        PopUp:SetScale(PopUp:GetScale() * self.tooltip:GetEffectiveScale() / PopUp:GetEffectiveScale())
    end
    PopUp:SetFrameLevel(self.tooltip:GetFrameLevel())

    if self.db.profile.options.popupRememberPosition then
        PopUp:ClearAllPoints()
        PopUp:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", self.db.profile.options.popupX, self.db.profile.options.popupY)
    end
end

function WQA:SortByZoneName(a, b)
    if a.type == "MISSION" and b.type ~= "MISSION" then
        return false
    elseif b.type == "MISSION" and a.type ~= "MISSION" then
        return true
    elseif a.type == "MISSION" and b.type == "MISSION" then
        return self:GetTaskZoneName(a) < self:GetTaskZoneName(b)
    end

    if a.type == "WORLD_QUEST" and WQA.questList[a.id].isEmissary ~= nil then
        if b.type == "WORLD_QUEST" and WQA.questList[b.id].isEmissary ~= nil then
            return false
        else
            return true
        end
    elseif b.type == "WORLD_QUEST" and WQA.questList[b.id].isEmissary ~= nil then
        return false
    end

    return self:GetTaskZoneName(a) < self:GetTaskZoneName(b)
end

function WQA:SortByExpansion(a, b)
    a = self:GetExpansion(a)

    b = self:GetExpansion(b)
    --returnself:GetExpansion(a) >self:GetExpansion(b)
    return a > b
end
