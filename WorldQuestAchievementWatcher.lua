---@class WorldQuestAchievementWatcher
local WQA = WorldQuestAchievementWatcher
 
local LibQTip = LibStub("LibQTip-1.0")
 
-- Blizzard
local IsActive = C_TaskQuest.IsActive
local GetQuestTagInfo = C_QuestLog.GetQuestTagInfo
local GetBountiesForMapID = C_QuestLog.GetBountiesForMapID
local GetTitleForQuestID = C_QuestLog.GetTitleForQuestID
local GetCurrencyLink = C_CurrencyInfo.GetCurrencyLink
local IsQuestFlaggedCompleted = C_QuestLog.IsQuestFlaggedCompleted
local L = WQA.L
 
local newOrder
do
	local current = 0
	function newOrder()
		current = current + 1
		return current
	end
end
 
WQA.data.custom = { wqID = "", rewardID = "", rewardType = "none", questType = "WORLD_QUEST" }
WQA.data.custom.mission = { missionID = "", rewardID = "", rewardType = "none" }
WQA.pendingQuests = {} -- Queue for targeted retries
 
local ldb = LibStub:GetLibrary("LibDataBroker-1.1")
local dataobj =
	ldb:NewDataObject(
		"WorldQuestAchievementWatcher",
		{
			type = "data source",
			text = "WQAW",
			icon = "Interface\\Icons\\INV_Misc_Map04"
		}
	)
 
local icon = LibStub("LibDBIcon-1.0")
 
function WQA:OnInitialize()
	-- Remove data for the other faction
	local faction = UnitFactionGroup("player")
	for k, v in pairs(self.data) do
		for kk, vv in pairs(v) do
			if type(vv) == "table" then
				for kkk, vvv in pairs(vv) do
					if vvv.faction and not (vvv.faction == faction) then
						self.data[k][kk][kkk] = nil
					end
				end
			end
		end
	end
	self.faction = faction
 
	-- Defaults
	local defaults = {
		char = {
			["*"] = {
				["profession"] = {
					["*"] = {
						isMaxLevel = true
					}
				}
			}
		},
		profile = {
			options = {
				["*"] = true,
				chat = true,
				PopUp = false,
				popupRememberPosition = false,
				popupX = 600,
				popupY = 800,
				zone = { ["*"] = true },
				reward = {
					gear = {
						["*"] = true,
						itemLevelUpgradeMin = 1,
						PercentUpgradeMin = 1,
						unknownSource = false,
						azeriteTraits = "",
						conduit = false
					},
					general = {
						gold = false,
						goldMin = 0,
						worldQuestType = {
							["*"] = true
						}
					},
					reputation = { ["*"] = false },
					currency = {},
					craftingreagent = { ["*"] = false },
					["*"] = {
						["*"] = true,
						profession = {
							["*"] = {
								skillup = true
							}
						}
					}
				},
				emissary = { ["*"] = false },
				missionTable = {
					reward = {
						gold = false,
						goldMin = 0,
						["*"] = {
							["*"] = false
						}
					}
				},
				delay = 5,
				LibDBIcon = { hide = false }
			},
			["achievements"] = { exclusive = {}, ["*"] = "default" },
			["mounts"] = { exclusive = {}, ["*"] = "default" },
			["pets"] = { exclusive = {}, ["*"] = "default" },
			["toys"] = { exclusive = {}, ["*"] = "default" },
			custom = {
				["*"] = { ["*"] = true }
			},
			["*"] = { ["*"] = true }
		},
		global = {
			completed = { ["*"] = false },
			custom = {
				["*"] = { ["*"] = false }
			}
		}
	}
	self.db = LibStub("AceDB-3.0"):New("WQAWDB", defaults, true)
 
	-- copy old data
	if type(self.db.global.custom) == "table" then
		for k, v in pairs(self.db.global.custom) do
			if type(k) == "number" then
				self.db.global.custom.worldQuest[k] = v
				self.db.global.custom[k] = nil
			end
		end
	end
	if type(self.db.global.customReward) == "table" then
		for k, v in pairs(self.db.global.customReward) do
			self.db.global.custom.worldQuestReward[k] = true
		end
		self.db.global.customReward = nil
	end
 
	-- Minimap Icon
	icon:Register("WorldQuestAchievementWatcher", dataobj, self.db.profile.options.LibDBIcon)
end
 

-- Retail 12.x exposes some rotating outdoor activities (including Cursed
-- Surges) through the Event Scheduler / Events tab rather than the normal
-- AreaPOI-for-map or TaskQuest lists. Cache the currently ongoing scheduler
-- events so achievement registration can treat them like ordinary Area POIs.
function WQA:RefreshEventSchedulerCache()
    self.eventSchedulerOngoing = {}
    self.eventSchedulerByPoi = {}

    local seen = {}
    local now = GetServerTime and GetServerTime() or time()

    local function cacheEvent(cached)
        if not cached or not cached.areaPoiID then
            return
        end

        local key = tostring(cached.areaPoiID) .. ":" .. tostring(cached.mapID) .. ":" .. tostring(cached.startTime or "") .. ":" .. tostring(cached.source or "")
        if seen[key] then
            return
        end
        seen[key] = true

        self.eventSchedulerOngoing[#self.eventSchedulerOngoing + 1] = cached
        if cached.mapID then
            self.eventSchedulerByPoi[cached.areaPoiID] = self.eventSchedulerByPoi[cached.areaPoiID] or {}
            self.eventSchedulerByPoi[cached.areaPoiID][cached.mapID] = cached
        end
    end

    local function resolveEvent(eventInfo, source)
        local poiID = eventInfo and eventInfo.areaPoiID
        if not poiID then return nil end
        local mapID = C_EventScheduler.GetEventUiMapID and C_EventScheduler.GetEventUiMapID(poiID) or nil
        local poiInfo = mapID and C_AreaPoiInfo.GetAreaPOIInfo(mapID, poiID) or nil
        return {
            areaPoiID = poiID,
            mapID = mapID,
            name = poiInfo and poiInfo.name or eventInfo.name,
            zoneName = C_EventScheduler.GetEventZoneName and C_EventScheduler.GetEventZoneName(poiID) or nil,
            rewardsClaimed = eventInfo.rewardsClaimed,
            startTime = eventInfo.startTime or eventInfo.eventStartTime,
            endTime = eventInfo.endTime or eventInfo.eventEndTime,
            eventID = eventInfo.eventID,
            eventKey = eventInfo.eventKey,
            source = source,
        }
    end

    if C_EventScheduler and (not C_EventScheduler.HasData or C_EventScheduler.HasData()) then
        if C_EventScheduler.GetOngoingEvents then
            for _, eventInfo in ipairs(C_EventScheduler.GetOngoingEvents() or {}) do
                cacheEvent(resolveEvent(eventInfo, "ongoing"))
            end
        end

        -- Rotating 12.1 public events can remain in the scheduled feed while
        -- their actual public-event phase is running. Treat a scheduled event
        -- whose [startTime, endTime) window contains the current server time as
        -- active. Do not register future events as active achievement tasks.
        if C_EventScheduler.GetScheduledEvents then
            for _, eventInfo in ipairs(C_EventScheduler.GetScheduledEvents() or {}) do
                local cached = resolveEvent(eventInfo, "scheduled")
                if cached and cached.startTime and cached.endTime and cached.startTime <= now and cached.endTime > now then
                    cacheEvent(cached)
                end
            end
        end
    end

end

function WQA:GetScheduledAreaPoiInfo(poiID, mapID)
    return self.eventSchedulerByPoi and self.eventSchedulerByPoi[poiID] and self.eventSchedulerByPoi[poiID][mapID] or nil
end

-- Some Midnight public events become outdoor scenarios once their active
-- phase begins. Cursed Surges are one example: the map/event scheduler can
-- stop exposing the event while C_ScenarioInfo still reports the live event
-- and its current stage. Keep this separate from Event Scheduler data so the
-- normal Area POI machinery can consume either source.
function WQA:GetActiveScenarioEvent()
    if not C_ScenarioInfo or not C_ScenarioInfo.GetScenarioInfo then
        return nil
    end

    local info = C_ScenarioInfo.GetScenarioInfo()
    if not info or not info.name or info.name == "" or info.isComplete then
        return nil
    end

    local step = C_ScenarioInfo.GetScenarioStepInfo and C_ScenarioInfo.GetScenarioStepInfo() or nil
    local scenarioID = tonumber(info.scenarioID) or 0

    return {
        areaPoiID = 1200000 + scenarioID,
        mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player") or nil,
        name = info.name,
        scenarioID = scenarioID,
        stepName = step and step.title or nil,
        currentStage = info.currentStage,
        numStages = info.numStages,
        source = "scenario",
    }
end

function WQA:GetScenarioAreaPoiInfo(poiID, mapID)
    local eventInfo = self:GetActiveScenarioEvent()
    if not eventInfo or eventInfo.areaPoiID ~= poiID then
        return nil
    end

    -- ROTATING_EVENT registration assigns the canonical achievement map ID.
    -- A live scenario can report a micro-map as the player's best map, so do
    -- not require the two map IDs to be identical here. The unique scenario
    -- pseudo-POI ID and name match performed during registration are enough.
    return eventInfo
end

function WQA:EnsureOptionsRegistered()
	if self.optionsRegistered then
		return true
	end

	-- Do not expose the full dynamic options tree to Blizzard Settings during
	-- login. It resolves many achievement/item/quest labels and can cause a
	-- large asynchronous data-loading burst even when no WQ scan is running.
	LibStub("AceConfig-3.0"):RegisterOptionsTable(
		"WorldQuestAchievementWatcher",
		function()
			return self:GetOptions()
		end
	)
	self.optionsFrame, self.optionsCategoryID = LibStub("AceConfigDialog-3.0"):AddToBlizOptions(
		"WorldQuestAchievementWatcher",
		"World Quest Achievement Watcher"
	)

	local profiles = LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db)
	LibStub("AceConfig-3.0"):RegisterOptionsTable("WQAWProfiles", profiles)
	self.optionsFrame.Profiles = LibStub("AceConfigDialog-3.0"):AddToBlizOptions(
		"WQAWProfiles",
		"Profiles",
		"World Quest Achievement Watcher"
	)

	self.optionsRegistered = true
	self:Debug("Options registered on demand")
	return true
end

function WQA:OnEnable()
	local name, server = UnitFullName("player")
	self.playerName = name .. "-" .. server

	-- Keep login initialization intentionally minimal. Settings registration is
	-- deferred until the player explicitly opens WQAW options.
	self.event = CreateFrame("Frame")
	self.event:RegisterEvent("PLAYER_ENTERING_WORLD")
	-- Garrison/mission, Event Scheduler, and scenario events are deliberately
	-- registered later, inside the first safe discovery window. Loading and
	-- servicing those systems during PLAYER_ENTERING_WORLD can create a long
	-- burst of Blizzard UI/data updates while the player is using quest NPCs.
	self.event:RegisterEvent("QUEST_TURNED_IN")
	-- Transmog listeners are registered only in the first safe refresh window.
	self.event:SetScript(
		"OnEvent",
		function(...)
			local _, name, id, arg2, arg3, arg4 = ...
			if name == "PLAYER_ENTERING_WORLD" then
				-- Login path: restore only local SavedVariables state, then become
				-- idle. No scan, Settings tree, collection listener, reward request,
				-- or repeating timer is started here.
				self.event:UnregisterEvent("PLAYER_ENTERING_WORLD")
				self:LoadPersistentDisplayCache()
				self.first = true
				self.quietStartupActive = true
				-- Do not arm a full discovery scan for the next World Map open.
				-- C_TaskQuest map/reward requests can keep Blizzard's quest system
				-- busy even after the map closes. Full scans are manual-only.
				self.pendingSafeDiscoveryMode = nil
				self.fullRefreshExplicitlyRequested = false
			elseif name == "ITEM_DATA_LOAD_RESULT" then
				self:HandleDisplayItemDataResult(id, arg2)
			elseif name == "QUEST_LOG_UPDATE" or name == "GET_ITEM_INFO_RECEIVED" then
				-- Debounce to prevent rapid-fire reward processing
				if self.rewardDebounceTimer then
					self:CancelTimer(self.rewardDebounceTimer)
				end
 
				self.rewardDebounceTimer = self:ScheduleTimer(function()
					self.event:UnregisterEvent("QUEST_LOG_UPDATE")
					self.event:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
					self:ProcessPendingRewards()
				end, 0.5)
			elseif name == "PLAYER_REGEN_ENABLED" then
				self.event:UnregisterEvent("PLAYER_REGEN_ENABLED")
				local deferredMode = self.deferredShowMode or "new"
				self.deferredShowMode = nil
				self:Show(deferredMode, true)
			elseif name == "QUEST_TURNED_IN" then
				self:HandleQuestTurnedIn(id)
			elseif name == "QUEST_FINISHED" or name == "GOSSIP_CLOSED" then
				if self.fullRefreshExplicitlyRequested then
					self:ScheduleTimer(function()
						if self.fullRefreshExplicitlyRequested and not self:IsQuestInteractionActive() then
							self:TryStartSafeDiscovery()
						end
					end, 0.10)
				else
					self.event:UnregisterEvent(name)
				end
			elseif name == "GARRISON_MISSION_LIST_UPDATE" then
				-- Do not inspect mission rewards directly from this event. Blizzard can
				-- fire it repeatedly while mission data is being initialized. Mark the
				-- snapshot dirty and fold it into the next safe full refresh instead.
				self.missionsDirty = true
				self.pendingSafeDiscoveryMode = self.pendingSafeDiscoveryMode or "new"
				if self.fullRefreshExplicitlyRequested and self:IsSafeWorldQuestDiscoveryWindow() then
					self:TryStartSafeDiscovery()
				end
			elseif name == "EVENT_SCHEDULER_UPDATE" then
				-- Scheduler updates are asynchronous and can arrive in bursts. Do not
				-- query AreaPOI/event data from them during normal play.
				self.eventSchedulerDirty = true
				self.pendingSafeDiscoveryMode = self.pendingSafeDiscoveryMode or "new"
				if self.fullRefreshExplicitlyRequested and self:IsSafeWorldQuestDiscoveryWindow() then
					self:TryStartSafeDiscovery()
				end
			elseif name == "TRANSMOG_COLLECTION_SOURCE_ADDED" or name == "TRANSMOG_COLLECTION_UPDATED" then
				if self.first and self.db.profile.options.reward.gear.unknownAppearance then
					local affected = {}
					if name == "TRANSMOG_COLLECTION_SOURCE_ADDED" then
						affected = self:GetTrackedTransmogQuestIDsForSource(id)
					elseif name == "TRANSMOG_COLLECTION_UPDATED" and arg3 then
						affected = MergeQuestIDSet(affected, self.activeTransmogAppearanceQuestIDs and self.activeTransmogAppearanceQuestIDs[arg3])
					end

					if next(affected) then
						self.pendingTransmogQuestRefresh = MergeQuestIDSet(self.pendingTransmogQuestRefresh or {}, affected)
						if self.transmogRefreshTimer then
							self:CancelTimer(self.transmogRefreshTimer)
						end
						self.transmogRefreshTimer = self:ScheduleTimer(function()
							self.transmogRefreshTimer = nil
							local quests = self.pendingTransmogQuestRefresh or {}
							self.pendingTransmogQuestRefresh = nil
							self:RefreshTrackedTransmogQuests(quests)
						end, 3)
					end
				end
			elseif name == "SCENARIO_UPDATE" or name == "SCENARIO_COMPLETED" then
				self.scenarioDirty = true
				self.pendingSafeDiscoveryMode = self.pendingSafeDiscoveryMode or "new"
				if self.fullRefreshExplicitlyRequested and self:IsSafeWorldQuestDiscoveryWindow() then
					self:TryStartSafeDiscovery()
				end
			end
		end
	)

	-- Retail's World Map and Quest Log share WorldMapFrame. WorldMapOnShow fires
	-- for both, so it must NOT be used as a scan trigger. Only an explicit
	-- ToggleWorldMap action arms the map refresh window.
	if type(ToggleWorldMap) == "function" and not self.worldMapToggleHookInstalled then
		self.worldMapToggleHookInstalled = true
		hooksecurefunc("ToggleWorldMap", function()
			self:ScheduleTimer(function()
				if WorldMapFrame and WorldMapFrame:IsShown() then
					self.explicitWorldMapRefreshWindow = true
					self.lastSafeWindowReason = "ToggleWorldMap"

					-- Opening M by itself is passive. Only resume/start a cross-
					-- expansion scan when the player explicitly requested one with
					-- an explicit refresh action.
					if self.fullRefreshExplicitlyRequested then
						self:TryStartSafeDiscovery()
					end
				else
					self.explicitWorldMapRefreshWindow = false
				end
			end, 0.05)
		end)
	end

	if EventRegistry and EventRegistry.RegisterCallback then
		EventRegistry:RegisterCallback("WorldMapOnHide", function()
			self.explicitWorldMapRefreshWindow = false
		end, self)
	end

	-- If quest details are opened while a map refresh is running, the scan will
	-- pause. Resume after the detail panel closes.
	local function ResumeAfterQuestDetails()
		self:ScheduleTimer(function()
			if self.fullRefreshExplicitlyRequested and not self:IsQuestInteractionActive() then
				self:TryStartSafeDiscovery()
			end
		end, 0.05)
	end

	if QuestMapFrame and QuestMapFrame.DetailsFrame and not self.questMapDetailsHookInstalled then
		self.questMapDetailsHookInstalled = true
		QuestMapFrame.DetailsFrame:HookScript("OnHide", ResumeAfterQuestDetails)
	end

	if QuestLogPopupDetailFrame and not self.questLogPopupHookInstalled then
		self.questLogPopupHookInstalled = true
		QuestLogPopupDetailFrame:HookScript("OnHide", ResumeAfterQuestDetails)
	end

	-- Event Scheduler and Blizzard_GarrisonUI are intentionally NOT initialized
	-- here. They are deferred until the first safe World Map/taxi refresh.
end
 
WQA:RegisterChatCommand("wqaw", "slash")
 
function WQA:slash(input)
	local arg1 = string.lower(input or "")

	if arg1 == "" then
		self:AnnounceChat(self.activeTasks or {})
	elseif arg1 == "new" then
		self:AnnounceChat(self.newTasks or {})
	elseif arg1 == "refresh" then
		self:RequestFullRefresh("manual /wqaw refresh", false)
	elseif arg1 == "popup" then
		self:Show("popup")
	elseif arg1 == "options" then
		self:EnsureOptionsRegistered()
		Settings.OpenToCategory(self.optionsCategoryID or (self.optionsFrame and self.optionsFrame.name))
	elseif arg1 == "debug" then
		local version = "unknown"
		if C_AddOns and C_AddOns.GetAddOnMetadata then
			version = C_AddOns.GetAddOnMetadata("WorldQuestAchievementWatcher", "Version") or version
		end
		print("|cff33ff99World Quest Achievement Watcher " .. tostring(version) .. "|r")
		print("Loaded: yes")
		print("Rewards ready: " .. tostring(self.rewards))
		print("Emissary rewards ready: " .. tostring(self.emissaryRewards))
		print("Pending reward quests: " .. (function() local n=0 for _ in pairs(self.pendingQuests or {}) do n=n+1 end return n end)())
		print("Reward preload queue: " .. tostring(self.rewardPreloadQueue and #self.rewardPreloadQueue or 0))
		print("Reward preload requests this scan: " .. tostring(self.rewardPreloadRequestsThisScan or 0))
		print("Reward preload paused for quest UI: " .. tostring(self.rewardPreloadPausedForQuestUI == true))
		print("World quest discovery scan active: " .. tostring(self.rewardScanInProgress == true))
		print("World quest discovery maps: " .. tostring(self.rewardScanMapsProcessed or 0) .. "/" .. tostring(self.rewardScanMaps and #self.rewardScanMaps or 0))
		print("World quest discovery quests processed: " .. tostring(self.rewardScanQuestsProcessed or 0))
		print("Full refresh map-data retries: " .. tostring(self.rewardScanMapRetries or 0))
		print("Full refresh unresolved maps: " .. tostring(self:CountTableEntries(self.rewardScanUnresolvedMaps)))
		print("Full refresh unresolved reward quests: " .. tostring(self:CountTableEntries(self.rewardScanUnresolvedRewardQuests)))
		print("World quest discovery paused for quest UI: " .. tostring(self.rewardScanPausedForQuestUI == true))
		print("World quest discovery paused for safe window: " .. tostring(self.rewardScanPausedForSafeWindow == true))
		print("World quest safe window active: " .. tostring(self:IsSafeWorldQuestDiscoveryWindow()))
		print("Explicit World Map refresh window: " .. tostring(self.explicitWorldMapRefreshWindow == true))
		print("Full refresh explicitly requested: " .. tostring(self.fullRefreshExplicitlyRequested == true))
		print("Full refresh settling: " .. tostring(self.fullRefreshSettling == true))
		print("Pending full refresh mode: " .. tostring(self.pendingSafeDiscoveryMode or "none"))
		print(self:GetLastFullScanStatusText())
		print("Full scan timestamp type: " .. type(self.worldQuestFullScanCompletedAt))
		print("Cached expiry timer active: " .. tostring(self.cachedWorldQuestExpiryTimer ~= nil))
		print("Quest log detail active: " .. tostring(self:IsQuestLogDetailActive()))
		print("Safe window reason: " .. tostring(self.lastSafeWindowReason or "none"))
		print("Persistent display cache available: " .. tostring(type(self.db.char.worldQuestDisplayCache) == "table" and type(self.db.char.worldQuestDisplayCache.activeTasks) == "table"))
		print("Quiet startup active: " .. tostring(self.quietStartupActive == true))
		print("Deferred data sources initialized: " .. tostring(self.deferredDataSourcesInitialized == true))
		print("Options registered: " .. tostring(self.optionsRegistered == true))
		print("Transmog listeners registered: " .. tostring(self.transmogListenersRegistered == true))
		print("Periodic refresh timer initialized: " .. tostring(self.periodicRefreshScheduled == true))
		print("Reward pending paused for safe window: " .. tostring(self.rewardPendingPausedForSafeWindow == true))
		print("Registered tracked quests: " .. (function() local n=0 for _ in pairs(self.questList or {}) do n=n+1 end return n end)())
		print("Chat output enabled: " .. tostring(self.db and self.db.profile.options.chat))
		print("Active scheduler events: " .. tostring(#(self.eventSchedulerOngoing or {})))
		local scenarioEvent = self:GetActiveScenarioEvent()
		if scenarioEvent then
			print("Active outdoor scenario: " .. tostring(scenarioEvent.name) .. " | stage=" .. tostring(scenarioEvent.currentStage) .. "/" .. tostring(scenarioEvent.numStages) .. " | step=" .. tostring(scenarioEvent.stepName))
		else
			print("Active outdoor scenario: none")
		end
	else
		print("|cff33ff99World Quest Achievement Watcher commands:|r /wqaw, /wqaw new, /wqaw refresh, /wqaw popup, /wqaw options, /wqaw debug")
	end
end

function WQA:CreateQuestList()
	self:Debug("CreateQuestList")
	if C_EventScheduler and C_EventScheduler.GetOngoingEvents and
		(not C_EventScheduler.HasData or C_EventScheduler.HasData()) then
		self:RefreshEventSchedulerCache()
		self.eventSchedulerDirty = false
	end
	self.scenarioDirty = false
	self.missionsDirty = false
	self.questList = {}
	-- Rebuilt on every full scan. These contain only transmog rewards currently
	-- relevant to active world quests, so unrelated collection changes do not
	-- trigger an expensive refresh.
	self.activeTransmogAppearanceIDs = {}
	self.activeTransmogSourceIDs = {}
	self.activeTransmogAppearanceQuestIDs = {}
	self.activeTransmogSourceQuestIDs = {}
	self.questPinList = {}
	self.questPinMapList = {}
	self.missionList = {}
	self.questFlagList = {}
	self.Criterias.AreaPoi.list = {}
	self.pendingQuests = {} -- Reset pending queue
 
	for expansionID = 7, 12 do
		local data = self.data[expansionID]
 
		if (data.achievements) then
			for _, v in pairs(data.achievements) do
				self.Achievements:Register(v)
			end
		end
 
		if (data.mounts) then
			self:AddMounts(data.mounts)
		end
 
		if (data.pets) then
			self:AddPets(data.pets)
		end
 
		if (data.toys) then
			self:AddToys(data.toys)
		end
	end
 
	self:AddCustom()
	self:Special()
	self:Reward()
	-- Emissary rewards are scanned after the paced world-quest discovery pass.
end
 
function WQA:AddMounts(mounts)
	for i, id in pairs(C_MountJournal.GetMountIDs()) do
		local n, spellID, _, _, _, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(id)
		local forced = false
 
		if
			not (self.db.profile.mounts[spellID] == "disabled" or
				(self.db.profile.mounts[spellID] == "exclusive" and self.db.profile.mounts.exclusive[spellID] ~= self.playerName))
		then
			if self.db.profile.mounts[spellID] == "always" then
				forced = true
			end
 
			if not isCollected or forced then
				for _, mount in pairs(mounts) do
					if spellID == mount.spellID then
						for _, v in pairs(mount.quest) do
							if not IsQuestFlaggedCompleted(v.trackingID or 0) then
								self:AddChanceRewardToQuest(v.wqID, mount.itemID, mount.name)
							end
						end
					end
				end
			end
		end
	end
end
 
function WQA:AddPets(pets)
	local total = C_PetJournal.GetNumPets()
	for i = 1, total do
		local petID, _, owned, _, _, _, _, _, _, _, companionID = C_PetJournal.GetPetInfoByIndex(i)
		local forced = false
 
		if
			not (self.db.profile.pets[companionID] == "disabled" or
				(self.db.profile.pets[companionID] == "exclusive" and self.db.profile.pets.exclusive[companionID] ~= self.playerName))
		then
			if self.db.profile.pets[companionID] == "always" then
				forced = true
			end
 
			if not owned or forced then
				for _, pet in pairs(pets) do
					if companionID == pet.creatureID then
						if pet.emissary == true then
							self:AddChanceRewardToQuest(pet.questID, pet.itemID, pet.name, true)
						end
 
						if pet.source and pet.source.type == "ITEM" then
							self.itemList[pet.source.itemID] = true
						end
 
						if pet.questID then
							self:AddChanceRewardToQuest(pet.questID, pet.itemID, pet.name)
						end
 
						if pet.quest then
							for _, v in pairs(pet.quest) do
								if not IsQuestFlaggedCompleted(v.trackingID) then
									self:AddChanceRewardToQuest(v.wqID, pet.itemID, pet.name)
								end
							end
						end
 
						break
					end
				end
			end
		end
	end
end
 
function WQA:AddToys(toys)
	for _, toy in pairs(toys) do
		local itemID = toy.itemID
		local forced = false
 
		if
			not (self.db.profile.toys[itemID] == "disabled" or
				(self.db.profile.toys[itemID] == "exclusive" and self.db.profile.toys.exclusive[itemID] ~= self.playerName))
		then
			if self.db.profile.toys[itemID] == "always" then
				forced = true
			end
 
			if not PlayerHasToy(toy.itemID) or forced then
				if toy.source and toy.source.type == "ITEM" then
					self.itemList[toy.source.itemID] = true
				else
					if toy.questID then
						self:AddChanceRewardToQuest(toy.questID, toy.itemID, toy.name)
					else
						for _, v in pairs(toy.quest) do
							if not IsQuestFlaggedCompleted(v.trackingID) then
								self:AddChanceRewardToQuest(v.wqID, toy.itemID, toy.name)
							end
						end
					end
				end
			end
		end
	end
end
 
function WQA:AddCustom()
	-- Custom World Quests
	if type(self.db.global.custom.worldQuest) == "table" then
		for questID, v in pairs(self.db.global.custom.worldQuest) do
			if self.db.profile.custom.worldQuest[questID] == true then
				self:AddRewardToQuest(questID, "CUSTOM")
				if v.questType == "QUEST_FLAG" then
					self.questFlagList[questID] = true
				elseif v.questType == "QUEST_PIN" and v.mapID then
					C_QuestLine.RequestQuestLinesForMap(v.mapID)
					self.questPinMapList[v.mapID] = true
					self.questPinList[questID] = true
				end
			end
		end
	end
 
	-- Custom Missions
	if type(self.db.global.custom.mission) == "table" then
		for k, v in pairs(self.db.global.custom.mission) do
			if self.db.profile.custom.mission[k] == true then
				self:AddRewardToMission(k, "CUSTOM")
			end
		end
	end
end
 
function WQA:AddRewardToMission(missionID, rewardType, reward)
	if not self.missionList[missionID] then
		self.missionList[missionID] = {}
	end
	local l = self.missionList[missionID]
 
	self:AddReward(l, rewardType, reward)
end
 
function WQA:AddRewardToQuest(questID, rewardType, reward, emissary)
	if not self.questList[questID] then
		self.questList[questID] = {}
	end
	local l = self.questList[questID]
 
	self:AddReward(l, rewardType, reward, emissary)
end

function WQA:SetChanceRewardDisplayName(questID, itemID, displayName)
	if not displayName then
		return
	end

	local quest = self.questList[questID]
	local chance = quest and quest.reward and quest.reward.chance
	if type(chance) ~= "table" then
		return
	end

	for _, reward in ipairs(chance) do
		if reward.id == itemID then
			reward.displayName = displayName
			return
		end
	end
end

function WQA:AddChanceRewardToQuest(questID, itemID, displayName, emissary)
	self:AddRewardToQuest(questID, "CHANCE", itemID, emissary)
	self:SetChanceRewardDisplayName(questID, itemID, displayName)
end
 
function WQA:AddEmissaryReward(questID, rewardType, reward)
	self:AddRewardToQuest(questID, rewardType, reward, true)
end
 
function WQA:CaptureQuestRefreshState()
	return {
		questList = self.questList,
		questPinList = self.questPinList,
		questPinMapList = self.questPinMapList,
		missionList = self.missionList,
		questFlagList = self.questFlagList,
		areaPoiList = self.Criterias.AreaPoi.list,
		pendingQuests = self.pendingQuests,
		rewards = self.rewards,
		emissaryRewards = self.emissaryRewards,
		activeTransmogAppearanceIDs = self.activeTransmogAppearanceIDs,
		activeTransmogSourceIDs = self.activeTransmogSourceIDs,
		activeTransmogAppearanceQuestIDs = self.activeTransmogAppearanceQuestIDs,
		activeTransmogSourceQuestIDs = self.activeTransmogSourceQuestIDs,
		activeTasks = self.activeTasks,
		newTasks = self.newTasks,
	}
end

function WQA:ApplyQuestRefreshState(state)
	if not state then
		return
	end

	self.questList = state.questList
	self.questPinList = state.questPinList
	self.questPinMapList = state.questPinMapList
	self.missionList = state.missionList
	self.questFlagList = state.questFlagList
	self.Criterias.AreaPoi.list = state.areaPoiList
	self.pendingQuests = state.pendingQuests
	self.rewards = state.rewards
	self.emissaryRewards = state.emissaryRewards
	self.activeTransmogAppearanceIDs = state.activeTransmogAppearanceIDs
	self.activeTransmogSourceIDs = state.activeTransmogSourceIDs
	self.activeTransmogAppearanceQuestIDs = state.activeTransmogAppearanceQuestIDs
	self.activeTransmogSourceQuestIDs = state.activeTransmogSourceQuestIDs
	self.activeTasks = state.activeTasks
	self.newTasks = state.newTasks
end

local function CopyPersistentValue(value, seen)
	local valueType = type(value)
	if valueType ~= "table" then
		if valueType == "number" or valueType == "string" or valueType == "boolean" then
			return value
		end
		return nil
	end

	seen = seen or {}
	if seen[value] then
		return seen[value]
	end

	local result = {}
	seen[value] = result
	for key, child in pairs(value) do
		local copiedKey = CopyPersistentValue(key, seen)
		local copiedValue = CopyPersistentValue(child, seen)
		if copiedKey ~= nil and copiedValue ~= nil then
			result[copiedKey] = copiedValue
		end
	end
	return result
end

function WQA:IsQuestLogDetailActive()
	if QuestLogPopupDetailFrame
		and QuestLogPopupDetailFrame.IsShown
		and QuestLogPopupDetailFrame:IsShown()
	then
		return true
	end

	if QuestMapFrame
		and QuestMapFrame.DetailsFrame
		and QuestMapFrame.DetailsFrame.IsShown
		and QuestMapFrame.DetailsFrame:IsShown()
		and QuestMapFrame.DetailsFrame.questID
	then
		return true
	end

	return false
end

function WQA:IsSafeWorldQuestDiscoveryWindow()
	-- Full cross-expansion discovery remains explicit-only, but it no longer
	-- requires the World Map to be open. The scan may run in the background as
	-- long as the player is not actively using quest/gossip/detail UI.
	if not self.fullRefreshExplicitlyRequested then
		return false
	end

	if self:IsQuestInteractionActive() then
		return false
	end

	return true
end

function WQA:SavePersistentDisplayCache()
	if not self.activeTasks or not self.questList then
		return
	end

	local now = GetServerTime and GetServerTime() or time()
	local previous = self.db.char.worldQuestDisplayCache
	local previousExpiry = {}
	if type(previous) == "table" and type(previous.activeTasks) == "table" then
		for _, task in ipairs(previous.activeTasks) do
			if task.type == "WORLD_QUEST" and task.expiresAt then
				previousExpiry[task.id] = task.expiresAt
			end
		end
	end

	-- Stamp expiry onto the live committed task objects as well as the
	-- persistent copy. During an explicit safe full scan the Blizzard API is
	-- allowed to provide fresh time-left data; outside that window we preserve
	-- the previously known absolute expiry and do not query the quest API.
	for _, task in ipairs(self.activeTasks) do
		if task.type == "WORLD_QUEST" then
			local expiresAt = task.expiresAt or previousExpiry[task.id]
			if self:IsSafeWorldQuestDiscoveryWindow() and C_TaskQuest.GetQuestTimeLeftMinutes then
				local minutes = C_TaskQuest.GetQuestTimeLeftMinutes(task.id)
				if minutes and minutes > 0 then
					expiresAt = now + (minutes * 60)
				end
			end
			task.expiresAt = expiresAt
		end
	end

	local cachedTasks = CopyPersistentValue(self.activeTasks) or {}

	self.db.char.worldQuestDisplayCache = {
		version = 1,
		savedAt = now,
		fullScanCompletedAt = type(self.worldQuestFullScanCompletedAt) == "number"
			and self.worldQuestFullScanCompletedAt
			or nil,
		questList = CopyPersistentValue(self.questList) or {},
		questPinList = CopyPersistentValue(self.questPinList) or {},
		questPinMapList = CopyPersistentValue(self.questPinMapList) or {},
		missionList = CopyPersistentValue(self.missionList) or {},
		questFlagList = CopyPersistentValue(self.questFlagList) or {},
		areaPoiList = CopyPersistentValue(self.Criterias.AreaPoi.list) or {},
		activeTransmogAppearanceIDs = CopyPersistentValue(self.activeTransmogAppearanceIDs) or {},
		activeTransmogSourceIDs = CopyPersistentValue(self.activeTransmogSourceIDs) or {},
		activeTransmogAppearanceQuestIDs = CopyPersistentValue(self.activeTransmogAppearanceQuestIDs) or {},
		activeTransmogSourceQuestIDs = CopyPersistentValue(self.activeTransmogSourceQuestIDs) or {},
		activeTasks = cachedTasks,
	}

	self:ScheduleNextCachedWorldQuestExpiry()
end

function WQA:LoadPersistentDisplayCache()
	local cache = self.db.char.worldQuestDisplayCache
	if type(cache) ~= "table" or cache.version ~= 1 or type(cache.activeTasks) ~= "table" then
		self.activeTasks = self.activeTasks or {}
		self.newTasks = {}
		self:UpdateLDBText(next(self.activeTasks), nil)
		self:Debug("No persistent display cache yet; open the world map once to seed it")
		return false
	end

	self.questList = CopyPersistentValue(cache.questList) or {}
	self.questPinList = CopyPersistentValue(cache.questPinList) or {}
	self.questPinMapList = CopyPersistentValue(cache.questPinMapList) or {}
	self.missionList = CopyPersistentValue(cache.missionList) or {}
	self.questFlagList = CopyPersistentValue(cache.questFlagList) or {}
	self.Criterias.AreaPoi.list = CopyPersistentValue(cache.areaPoiList) or {}
	self.activeTransmogAppearanceIDs = CopyPersistentValue(cache.activeTransmogAppearanceIDs) or {}
	self.activeTransmogSourceIDs = CopyPersistentValue(cache.activeTransmogSourceIDs) or {}
	self.activeTransmogAppearanceQuestIDs = CopyPersistentValue(cache.activeTransmogAppearanceQuestIDs) or {}
	self.activeTransmogSourceQuestIDs = CopyPersistentValue(cache.activeTransmogSourceQuestIDs) or {}
	self.activeTasks = CopyPersistentValue(cache.activeTasks) or {}
	self.newTasks = {}
	self.pendingQuests = {}
	self.rewards = true
	self.emissaryRewards = true
	local cachedFullScanAt = cache.fullScanCompletedAt
	if type(cachedFullScanAt) ~= "number" and type(cache.lastFullScanAt) == "number" then
		-- One-time compatibility with the first cache-maintenance test build.
		cachedFullScanAt = cache.lastFullScanAt
	end

	if type(cachedFullScanAt) == "number" then
		self.worldQuestFullScanCompletedAt = cachedFullScanAt
	else
		self.worldQuestFullScanCompletedAt = nil
	end

	-- Remove anything that expired while the character was offline before the
	-- restored list is shown. This uses only cached absolute timestamps.
	self:PruneExpiredCachedWorldQuests(true)

	for _, task in ipairs(self.activeTasks) do
		if task.type == "WORLD_QUEST" then
			self.watched[task.id] = true
		elseif task.type == "MISSION" then
			self.watchedMissions[task.id] = true
		elseif task.type == "AREA_POI" then
			self.Criterias.AreaPoi.watched[task.id] = self.Criterias.AreaPoi.watched[task.id] or {}
			self.Criterias.AreaPoi.watched[task.id][task.mapId] = true
		end
	end

	self:UpdateLDBText(next(self.activeTasks), nil)
	self:ScheduleNextCachedWorldQuestExpiry()
	self:Debug("Loaded persistent WQ display cache", #self.activeTasks, "tasks")
	return true
end

function WQA:InitializeDeferredDataSources()
	if self.deferredDataSourcesInitialized then
		return
	end

	self.deferredDataSourcesInitialized = true
	self.quietStartupActive = false

	-- GetPrimaryGarrisonFollowerType and some mission-table helpers live in the
	-- Blizzard Garrison UI addon on some clients. If it is needed, load it only
	-- while the World Map/taxi safe window is already active. Register the
	-- mission event afterwards so its initialization burst cannot invoke WQAW.
	if C_AddOns and C_AddOns.LoadAddOn then
		pcall(C_AddOns.LoadAddOn, "Blizzard_GarrisonUI")
	end
	self.event:RegisterEvent("GARRISON_MISSION_LIST_UPDATE")

	-- Collection events are intentionally deferred so the login-time
	-- transmog collection population cannot make WQAW do background work.
	self.event:RegisterEvent("TRANSMOG_COLLECTION_SOURCE_ADDED")
	self.event:RegisterEvent("TRANSMOG_COLLECTION_UPDATED")
	self.transmogListenersRegistered = true

	self.event:RegisterEvent("EVENT_SCHEDULER_UPDATE")
	self.event:RegisterEvent("SCENARIO_UPDATE")
	self.event:RegisterEvent("SCENARIO_COMPLETED")

	if C_EventScheduler and C_EventScheduler.RequestEvents then
		C_EventScheduler.RequestEvents()
		if not C_EventScheduler.HasData or C_EventScheduler.HasData() then
			self:RefreshEventSchedulerCache()
			self.eventSchedulerDirty = false
		end
	end

	-- Periodic freshness starts only after WQAW has entered a deliberate safe
	-- window once. A periodic tick can queue work, but cannot scan during normal
	-- quest-giver interaction.
	if not self.periodicRefreshScheduled then
		self.periodicRefreshScheduled = true
		self:ScheduleRepeatingTimer(function()
			-- Mark the cached list as needing a future full refresh, but never
			-- start cross-expansion quest API work automatically.
			self.pendingSafeDiscoveryMode = self.pendingSafeDiscoveryMode or "new"
		end, 30 * 60)
	end

	self:Debug("Deferred WQAW data sources initialized in safe window")
end

local FULL_REFRESH_SETTLE_SECONDS = 10

function WQA:BeginFullRefreshSettlingPeriod()
	if self.fullRefreshSettleTimer then
		self:CancelTimer(self.fullRefreshSettleTimer)
		self.fullRefreshSettleTimer = nil
	end

	self.fullRefreshSettling = true
	self.fullRefreshSettlesAt = (GetTime and GetTime() or 0) + FULL_REFRESH_SETTLE_SECONDS

	print(
		"|cff33ff99WQAW:|r Full scan complete. "
			.. "Waiting "
			.. tostring(FULL_REFRESH_SETTLE_SECONDS)
			.. " seconds for Blizzard quest data to settle..."
	)

	self.fullRefreshSettleTimer = self:ScheduleTimer(function()
		self.fullRefreshSettleTimer = nil
		self.fullRefreshSettling = false
		self.fullRefreshSettlesAt = nil
		print("|cff33ff99WQAW:|r Full refresh finished.")
	end, FULL_REFRESH_SETTLE_SECONDS)
end

function WQA:RequestFullRefresh(reason, openWorldMap)
	reason = reason or "manual refresh"

	if self.fullRefreshSettling then
		local remaining = 0
		if self.fullRefreshSettlesAt and GetTime then
			remaining = math.max(0, math.ceil(self.fullRefreshSettlesAt - GetTime()))
		end

		print(
			"|cff33ff99WQAW:|r Blizzard quest data is still settling"
				.. (remaining > 0 and (" (" .. tostring(remaining) .. "s remaining).") or ".")
		)
		return false
	end

	if self.fullRefreshExplicitlyRequested then
		print("|cff33ff99WQAW:|r Full refresh is already in progress.")
		return false
	end

	self.pendingSafeDiscoveryMode = "new"
	self.fullRefreshExplicitlyRequested = true
	self.lastSafeWindowReason = reason

	-- These events are used only while an explicit full refresh is pending.
	-- If the scan pauses because the player opens quest/gossip UI, closing that
	-- interaction resumes the same refresh automatically.
	self.event:RegisterEvent("QUEST_FINISHED")
	self.event:RegisterEvent("GOSSIP_CLOSED")

	print("|cff33ff99WQAW:|r Full refresh requested.")

	if self:IsQuestInteractionActive() then
		print("|cff33ff99WQAW:|r Waiting for the current quest interaction to finish.")
		return false
	end

	return self:TryStartSafeDiscovery()
end

function WQA:TryStartSafeDiscovery()
	-- Full cross-expansion discovery is explicit-only. Once requested it may
	-- run in the background, but it pauses whenever quest/gossip/detail UI is
	-- active.
	if not self.fullRefreshExplicitlyRequested then
		return false
	end

	if not self:IsSafeWorldQuestDiscoveryWindow() then
		return false
	end

	self:InitializeDeferredDataSources()

	-- Resume reward work that was deliberately stopped rather than polled while
	-- the safe window was closed.
	if self.rewardPreloadPausedForSafeWindow and self.rewardPreloadQueue and #self.rewardPreloadQueue > 0 then
		self.rewardPreloadPausedForSafeWindow = false
		self:StartRewardPreloadQueue(0.05)
	end
	if self.rewardPendingPausedForSafeWindow and self.pendingQuests and next(self.pendingQuests) then
		self.rewardPendingPausedForSafeWindow = false
		self:SchedulePendingRewardCheck(0.10)
	end

	-- Resume an interrupted explicit discovery as soon as quest interaction
	-- is no longer blocking it.
	if self.rewardScanInProgress then
		self.rewardScanPausedForSafeWindow = false
		if self.rewardScanTimer then
			self:CancelTimer(self.rewardScanTimer)
			self.rewardScanTimer = nil
		end
		self:ScheduleRewardScanStep(0.01)
		return true
	end

	if self.backgroundScanInProgress then
		self:ScheduleTimer(function()
			self:TryStartSafeDiscovery()
		end, 0.25)
		return false
	end

	-- Only an explicit user refresh action queues a full scan.
	local mode = self.pendingSafeDiscoveryMode
	if not mode then
		return false
	end

	self.pendingSafeDiscoveryMode = nil
	self:Show(mode, true)
	return true
end

function WQA:WithCommittedScanState(callback)
	if type(callback) ~= "function" then
		return
	end

	if self.backgroundScanInProgress and self.backgroundScanCommittedState then
		local buildState = self:CaptureQuestRefreshState()
		self:ApplyQuestRefreshState(self.backgroundScanCommittedState)

		local ok, err = pcall(callback)

		self:ApplyQuestRefreshState(buildState)

		if not ok then
			error(err)
		end
		return
	end

	callback()
end

function WQA:FinishBackgroundScan(mode)
	if not self.backgroundScanInProgress then
		return
	end

	local completedExplicitFullRefresh = self.fullRefreshExplicitlyRequested == true

	self.backgroundScanInProgress = false
	self.backgroundScanCommittedState = nil
	self.backgroundScanMode = nil

	-- One explicit /wqaw refresh authorizes one complete cross-expansion scan.
	-- After it commits, opening M goes back to being completely passive.
	self.fullRefreshExplicitlyRequested = false

	if completedExplicitFullRefresh then
		local now = GetServerTime and GetServerTime() or time()
		self.worldQuestFullScanCompletedAt = now

		-- CheckWQ saved the completed quest snapshot immediately before this
		-- function. Save once more so the authoritative full-scan timestamp is
		-- persisted with that same snapshot.
		self:SavePersistentDisplayCache()

		self.event:UnregisterEvent("QUEST_FINISHED")
		self.event:UnregisterEvent("GOSSIP_CLOSED")
		self:BeginFullRefreshSettlingPeriod()
	end

	self:RefreshVisibleTaskList()

	local queuedMode = self.backgroundScanQueuedMode
	self.backgroundScanQueuedMode = nil

	if queuedMode then
		self:ScheduleTimer(function()
			if queuedMode == "all" then
				self:Show(nil, true)
			else
				self:Show(queuedMode, true)
			end
		end, 0.5)
	end
end

function WQA:EnterSilentBuildState()
	if not self.silentRefreshInProgress
		or self.silentBuildStateActive
		or not self.silentBuildState
	then
		return false
	end

	self:ApplyQuestRefreshState(self.silentBuildState)
	self.silentBuildStateActive = true
	return true
end

function WQA:ExitSilentBuildState(enteredBuildState, commit)
	if not enteredBuildState then
		return
	end

	self.silentBuildState = self:CaptureQuestRefreshState()
	self.silentBuildStateActive = false

	if commit then
		-- The build state is already live. It becomes the new committed state.
		self.silentCommittedState = nil
		self.silentBuildState = nil
	else
		-- Keep the last fully valid list available to the minimap icon while
		-- asynchronous reward data continues loading in the background.
		self:ApplyQuestRefreshState(self.silentCommittedState)
	end
end

local function RemoveWorldQuestFromTaskList(tasks, questID)
	if type(tasks) ~= "table" then
		return false
	end

	local removed = false

	for index = #tasks, 1, -1 do
		local task = tasks[index]
		if task and task.type == "WORLD_QUEST" and task.id == questID then
			table.remove(tasks, index)
			removed = true
		end
	end

	return removed
end

function WQA:GetLastFullScanStatusText()
	local lastScan = self.worldQuestFullScanCompletedAt

	if type(lastScan) ~= "number" then
		local cache = self.db.char.worldQuestDisplayCache
		if type(cache) == "table" then
			if type(cache.fullScanCompletedAt) == "number" then
				lastScan = cache.fullScanCompletedAt
			elseif type(cache.lastFullScanAt) == "number" then
				-- Compatibility with a valid numeric value written by the first
				-- cache-maintenance test build. Table values are deliberately ignored.
				lastScan = cache.lastFullScanAt
			end
		end
	end

	if type(lastScan) ~= "number" then
		return "Last full scan: not recorded"
	end

	local now = GetServerTime and GetServerTime() or time()
	local age = math.max(0, now - lastScan)

	if age < 60 then
		return "Last full scan: just now"
	end

	local minutes = math.floor(age / 60)
	if minutes < 60 then
		return string.format("Last full scan: %dm ago", minutes)
	end

	local hours = math.floor(minutes / 60)
	local remainderMinutes = minutes % 60
	if hours < 24 then
		if remainderMinutes > 0 then
			return string.format("Last full scan: %dh %dm ago", hours, remainderMinutes)
		end
		return string.format("Last full scan: %dh ago", hours)
	end

	local days = math.floor(hours / 24)
	local remainderHours = hours % 24
	if remainderHours > 0 then
		return string.format("Last full scan: %dd %dh ago", days, remainderHours)
	end
	return string.format("Last full scan: %dd ago", days)
end

function WQA:ScheduleNextCachedWorldQuestExpiry()
	if self.cachedWorldQuestExpiryTimer then
		self:CancelTimer(self.cachedWorldQuestExpiryTimer)
		self.cachedWorldQuestExpiryTimer = nil
	end

	local tasks = self.activeTasks
	if self.backgroundScanInProgress
		and self.backgroundScanCommittedState
		and self.backgroundScanCommittedState.activeTasks
	then
		tasks = self.backgroundScanCommittedState.activeTasks
	end

	if type(tasks) ~= "table" then
		return
	end

	local now = GetServerTime and GetServerTime() or time()
	local earliest

	for _, task in ipairs(tasks) do
		if task.type == "WORLD_QUEST"
			and type(task.expiresAt) == "number"
			and task.expiresAt > now
			and (not earliest or task.expiresAt < earliest)
		then
			earliest = task.expiresAt
		end
	end

	if not earliest then
		return
	end

	local delay = math.max(1, earliest - now + 1)
	self.cachedWorldQuestExpiryTimer = self:ScheduleTimer(function()
		self.cachedWorldQuestExpiryTimer = nil
		self:PruneExpiredCachedWorldQuests(false)
		self:ScheduleNextCachedWorldQuestExpiry()
	end, delay)
end

function WQA:PruneExpiredCachedWorldQuests(suppressVisibleRefresh)
	local now = GetServerTime and GetServerTime() or time()
	local removedQuestIDs = {}

	self:WithCommittedScanState(function()
		for index = #(self.activeTasks or {}), 1, -1 do
			local task = self.activeTasks[index]
			if task
				and task.type == "WORLD_QUEST"
				and type(task.expiresAt) == "number"
				and task.expiresAt <= now
			then
				removedQuestIDs[task.id] = true
				table.remove(self.activeTasks, index)
			end
		end

		for questID in pairs(removedQuestIDs) do
			RemoveWorldQuestFromTaskList(self.newTasks, questID)

			if self.questList then
				self.questList[questID] = nil
			end
			if self.questPinList then
				self.questPinList[questID] = nil
			end
			if self.questFlagList then
				self.questFlagList[questID] = nil
			end

			self:RemoveQuestFromTransmogTracking(questID)
		end

		if next(removedQuestIDs) then
			self.activeTasks = self:SortQuestList(self.activeTasks or {})
			self.newTasks = self:SortQuestList(self.newTasks or {})
			self:UpdateLDBText(next(self.activeTasks), next(self.newTasks))
			self:SavePersistentDisplayCache()
		end
	end)

	local removedCount = 0
	for _ in pairs(removedQuestIDs) do
		removedCount = removedCount + 1
	end

	if removedCount > 0 then
		self:Debug("Pruned expired cached world quests", removedCount)
		if not suppressVisibleRefresh then
			self:RefreshVisibleTaskList()
		end
	end

	return removedCount
end

function WQA:ResizeOpenPopupToTooltip()
	if not self.tooltip or not self.PopUp or not self.PopUp.shown then
		return
	end

	local PopUp = self.PopUp
	PopUp:SetWidth(self.tooltip:GetWidth() + 8.5)
	PopUp:SetHeight(self.tooltip:GetHeight() + 32)
	PopUp:SetScale(self.tooltip:GetScale())

	if PopUp:GetEffectiveScale() ~= self.tooltip:GetEffectiveScale() then
		PopUp:SetScale(
			PopUp:GetScale()
				* self.tooltip:GetEffectiveScale()
				/ PopUp:GetEffectiveScale()
		)
	end

	PopUp:SetFrameLevel(self.tooltip:GetFrameLevel())
end

function WQA:RefreshVisibleTaskList()
	if not self.tooltip then
		return
	end

	self:WithCommittedScanState(function()
		self:UpdateQTip(self.activeTasks or {})
		self:ResizeOpenPopupToTooltip()
	end)
end

function WQA:HandleQuestTurnedIn(questID)
	self.db.global.completed[questID] = true

	-- Once Blizzard marks a world quest complete, C_TaskQuest can stop
	-- returning its zone/map immediately. If the old cached task remains
	-- visible until the later transmog refresh, the tooltip can therefore
	-- temporarily sort it under "Unknown".
	--
	-- Remove the completed quest from every committed snapshot immediately.
	local removed = RemoveWorldQuestFromTaskList(self.activeTasks, questID)
	RemoveWorldQuestFromTaskList(self.newTasks, questID)

	if self.silentCommittedState then
		RemoveWorldQuestFromTaskList(self.silentCommittedState.activeTasks, questID)
		RemoveWorldQuestFromTaskList(self.silentCommittedState.newTasks, questID)
	end

	if self.silentBuildState then
		RemoveWorldQuestFromTaskList(self.silentBuildState.activeTasks, questID)
		RemoveWorldQuestFromTaskList(self.silentBuildState.newTasks, questID)
	end

	if self.backgroundScanCommittedState then
		if RemoveWorldQuestFromTaskList(self.backgroundScanCommittedState.activeTasks, questID) then
			removed = true
		end
		RemoveWorldQuestFromTaskList(self.backgroundScanCommittedState.newTasks, questID)
	end

	if removed then
		self:Debug("Removing completed world quest from committed list", questID)
		self:UpdateLDBText(
			self.activeTasks and next(self.activeTasks) or nil,
			self.newTasks and next(self.newTasks) or nil
		)
		self:RefreshVisibleTaskList()
		self:SavePersistentDisplayCache()
	end
end

WQA.first = false
function WQA:Show(mode, auto)
	-- Hover and left-click both use the same last fully committed activeTasks
	-- snapshot. Opening the popup is a UI action, not a reason to perform a
	-- fresh full quest/reward scan.
	if mode == "popup" then
		self:PruneExpiredCachedWorldQuests(false)
		self.popupRequestActive = true
		self:WithCommittedScanState(function()
			self:AnnouncePopUp(self.activeTasks or {})
		end)
		return
	end

	-- An explicit full discovery may run without the World Map, but never while
	-- the player is actively using quest/gossip/detail UI.
	if not self:IsSafeWorldQuestDiscoveryWindow() then
		self.pendingSafeDiscoveryMode = mode or "new"
		self:Debug("Deferring full WQ discovery until quest interaction is clear", tostring(self.pendingSafeDiscoveryMode))
		return
	end

	if self.backgroundScanInProgress then
		self.backgroundScanQueuedMode = mode or "all"
		self:Debug("Full scan already in progress - queueing", tostring(self.backgroundScanQueuedMode))
		return
	end

	-- If another relevant appearance is learned while this silent transaction
	-- is still in flight, queue one additional pass rather than overlapping
	-- two CreateQuestList() rebuilds.
	if mode == "silent" and self.silentRefreshInProgress then
		self.silentRefreshAgain = true
		self:Debug("Silent refresh already in progress - queueing another pass")
		return
	end
	if auto and self.db.profile.options.delayCombat == true and UnitAffectingCombat("player") then
		self.deferredShowMode = mode
		self.event:RegisterEvent("PLAYER_REGEN_ENABLED")
		return
	end
	self:Debug("Show", mode)

	if mode == "popup" then
		self.popupRequestActive = true
	end

	-- Keep the last complete quest snapshot available to the minimap UI while
	-- the new discovery scan is built cooperatively in the background.
	self.backgroundScanCommittedState = self:CaptureQuestRefreshState()
	self.backgroundScanInProgress = true
	self.backgroundScanMode = mode or "all"
	self.rewardContinuationMode = self.backgroundScanMode

	-- A silent transmog refresh may need to wait for reward/item data after
	-- CreateQuestList() returns. Keep its mode available to those asynchronous
	-- callbacks without replacing lastMode, which is reserved for normal scans.
	if mode == "silent" then
		self.pendingRefreshMode = "silent"
		self.silentRefreshInProgress = true
		self.silentRefreshBuilding = true
		self.silentCommittedState = self:CaptureQuestRefreshState()
		self.silentBuildState = nil
		self.silentBuildStateActive = true
	else
		-- A newer normal/manual refresh supersedes an unfinished silent refresh.
		self.pendingRefreshMode = nil
		self.silentRefreshInProgress = false
		self.silentRefreshBuilding = false
		self.silentRefreshAgain = nil
		self.silentCommittedState = nil
		self.silentBuildState = nil
		self.silentBuildStateActive = false
	end

	self:CreateQuestList()

	if mode == "silent" then
		self.silentRefreshBuilding = false
	end

	-- "popup", "LDB", and "silent" are transient UI/maintenance requests. Do
	-- not remember them as the mode delayed reward/event processing should use
	-- for future normal scans.
	if mode ~= "popup" and mode ~= "LDB" and mode ~= "silent" then
		self.lastMode = mode
	end

	self:CheckWQ(mode)

	if mode == "silent" and self.silentRefreshInProgress then
		-- CheckWQ did not commit yet. Preserve the partially built state for
		-- reward callbacks, then put the previous complete state back live so
		-- minimap hover/click remains fully usable.
		self.silentBuildState = self:CaptureQuestRefreshState()
		self.silentBuildStateActive = false
		self:ApplyQuestRefreshState(self.silentCommittedState)
	elseif mode == "silent" then
		-- The refresh completed synchronously and the new state is already live.
		self.silentCommittedState = nil
		self.silentBuildState = nil
		self.silentBuildStateActive = false
	end

	self.first = true
end
 
function WQA:CheckWQ(mode)
	local enteredSilentBuildState = self:EnterSilentBuildState()

	-- Passive reward/event callbacks use lastMode. Never let a manual popup,
	-- minimap-tooltip request, or silent maintenance refresh become the mode
	-- they replay later.
	if mode ~= "popup" and mode ~= "LDB" and mode ~= "silent" then
		self.lastMode = mode
	end
	self:Debug("CheckWQ")

	-- World-quest discovery is now cooperative/asynchronous. Keep the last
	-- committed list visible until every enabled map has been inspected.
	if self.rewardScanInProgress then
		self:Debug("Reward discovery still in progress - keeping committed list")
		self:ExitSilentBuildState(enteredSilentBuildState, false)
		return
	end

	-- Never publish an explicit full refresh while map/reward data is incomplete.
	if self.backgroundScanInProgress then
		local hasPendingRewards = self.pendingQuests and next(self.pendingQuests) ~= nil

		if self.rewards ~= true or self.emissaryRewards ~= true or hasPendingRewards then
			self:Debug(
				"Full refresh waiting for complete reward data",
				"rewards=" .. tostring(self.rewards),
				"emissary=" .. tostring(self.emissaryRewards),
				"pending=" .. tostring(hasPendingRewards)
			)
			self:ExitSilentBuildState(enteredSilentBuildState, false)
			return
		end

		local complete, unresolvedMaps, unresolvedRewards, pendingRewards =
			self:IsFullRefreshSnapshotComplete()

		if not complete then
			self:ExitSilentBuildState(enteredSilentBuildState, false)
			self:AbortIncompleteFullRefresh(
				unresolvedMaps,
				unresolvedRewards,
				pendingRewards
			)
			return
		end
	end


	-- Silent transmog refreshes are transactional. CreateQuestList() rebuilds
	-- questList/missionList immediately, while reward data can arrive over
	-- several asynchronous callbacks. Do not publish any of those intermediate
	-- states to activeTasks or the tooltip.
	if mode == "silent" and self.silentRefreshInProgress then
		local hasPendingRewards = self.pendingQuests and next(self.pendingQuests) ~= nil

		if self.silentRefreshBuilding
			or self.rewards ~= true
			or self.emissaryRewards ~= true
			or hasPendingRewards
		then
			self:Debug(
				"Silent refresh waiting for complete reward data",
				"building=" .. tostring(self.silentRefreshBuilding),
				"rewards=" .. tostring(self.rewards),
				"emissary=" .. tostring(self.emissaryRewards),
				"pending=" .. tostring(hasPendingRewards)
			)
			self:ExitSilentBuildState(enteredSilentBuildState, false)
			return
		end
	end
 
	-- Retail 12.1.0 can leave old item/reward data uncached indefinitely.
	-- Do not block the entire quest scan while waiting for every reward link.
	-- Active quest detection is authoritative; reward links are best-effort.
	if self.rewards ~= true or self.emissaryRewards ~= true then
		self:Debug("Reward cache incomplete - continuing scan")
	end
 
	local activeQuests = {}
	local newQuests = {}
	local retry = false
	for questID, _ in pairs(self.questList) do
		if
			IsActive(questID) or self:EmissaryIsActive(questID) or self:isQuestPinActive(questID) or
			self:IsQuestFlaggedCompleted(questID)
		then
			local questLink = self:GetTaskLink({ id = questID, type = "WORLD_QUEST" })
			local link
			for k, v in pairs(self.questList[questID].reward) do
				if k == "custom" or k == "professionSkillup" or k == "gold" then
					link = true
				else
					link = self:GetRewardLinkByID(questID, k, v, 1)
				end
				if not link then
					self:Debug("Reward link unavailable", questID, k, v, 1)
				else
					self:SetRewardLinkByID(questID, k, v, 1, link)
				end
 
				if k == "achievement" or k == "chance" or k == "azeriteTraits" then
					for i = 2, #v do
						link = self:GetRewardLinkByID(questID, k, v, i)
						if not link then
							self:Debug("Reward link unavailable", questID, k, v, i)
						else
							self:SetRewardLinkByID(questID, k, v, i, link)
						end
					end
				end
			end
			if not questLink then
				self:Debug("Quest link unavailable", questID)
				retry = true
			else
				activeQuests[questID] = true
				if not self.watched[questID] then
					newQuests[questID] = true
				end
			end
		end
	end
 
	local activeMissions = self:CheckMissions()
	local newMissions = {}
	if type(activeMissions) == "table" then
		for missionID, _ in pairs(activeMissions) do
			local link = false
			for k, v in pairs(self.missionList[missionID].reward) do
				if k == "custom" or k == "professionSkillup" or k == "gold" then
					link = true
				else
					link = self:GetRewardLinkByMissionID(missionID, k, v, 1)
				end
				if not link then
					retry = true
				else
					self:SetRewardLinkByMissionID(missionID, k, v, 1, link)
				end
			end
			if not link then
				retry = true
			else
				if not self.watchedMissions[missionID] then
					newMissions[missionID] = true
				end
			end
		end
	else
		retry = true
	end
 
	local pois = self.Criterias.AreaPoi:Check()
 
	if pois.retry then
		retry = true
	end
 
	if retry == true then
		self:Debug("NoLink")
		-- Gentle fallback just in case links are extremely stubborn
		self:ScheduleTimer("CheckWQ", 1, mode)
		self:ExitSilentBuildState(enteredSilentBuildState, false)
		return
	end
 
	self.activeTasks = {}
	for id in pairs(activeQuests) do
		local mapID = self.questList[id] and self.questList[id].scanMapID
		table.insert(self.activeTasks, { id = id, type = "WORLD_QUEST", mapId = mapID })
	end
	for id in pairs(activeMissions) do
		table.insert(self.activeTasks, { id = id, type = "MISSION" })
	end
	for poiId, mapIds in pairs(pois.active) do
		for mapId in pairs(mapIds) do
			table.insert(self.activeTasks, { id = poiId, mapId = mapId, type = "AREA_POI" })
		end
	end
 
	self.activeTasks = self:SortQuestList(self.activeTasks)
 
	self.newTasks = {}

	-- A silent maintenance refresh must update activeTasks without consuming
	-- the "new" state. If a genuinely new quest appeared at the same time the
	-- player learned a transmog, the next normal scan should still announce it.
	if mode ~= "silent" then
		for id in pairs(newQuests) do
			self.watched[id] = true
			table.insert(self.newTasks, { id = id, type = "WORLD_QUEST" })
		end
		for id in pairs(newMissions) do
			self.watchedMissions[id] = true
			table.insert(self.newTasks, { id = id, type = "MISSION" })
		end
		for poiId, mapIds in pairs(pois.new) do
			for mapId in pairs(mapIds) do
				if not self.Criterias.AreaPoi.watched[poiId] then
					self.Criterias.AreaPoi.watched[poiId] = {}
				end
				self.Criterias.AreaPoi.watched[poiId][mapId] = true

				table.insert(self.newTasks, { id = poiId, mapId = mapId, type = "AREA_POI" })
			end
		end
	end
 
	-- activeTasks is already sorted above. newTasks is assembled from pairs(),
	-- so sort it before any chat/popup rendering as well to keep expansion and
	-- zone headers contiguous.
	self.newTasks = self:SortQuestList(self.newTasks)

	if mode == "silent" then
		-- No chat announcement and no new popup. Update whichever committed
		-- tooltip/popup is currently visible only after the silent build is ready.
		self:RefreshVisibleTaskList()
	elseif mode == "new" then
		self:AnnounceChat(self.newTasks, self.first)
		if self.db.profile.options.PopUp == true then
			self:AnnouncePopUp(self.newTasks, self.first)
		end
	elseif mode == "popup" then
		if self.popupRequestActive then
			self:AnnouncePopUp(self.activeTasks)
		end
	elseif mode == "LDB" then
		self:AnnounceLDB(self.activeTasks)
	else
		self:AnnounceChat(self.activeTasks)
		if self.db.profile.options.PopUp == true then
			self:AnnouncePopUp(self.activeTasks)
		end
	end

	self:UpdateLDBText(next(self.activeTasks), next(self.newTasks))
	self:SavePersistentDisplayCache()

	-- Reaching this point means the silent transaction produced a complete,
	-- internally consistent list. Commit it once and release silent mode.
	if mode == "silent" and self.silentRefreshInProgress then
		self.pendingRefreshMode = nil
		self.silentRefreshInProgress = false
		self.silentRefreshBuilding = false

		-- If another matching appearance was learned while this transaction was
		-- still resolving, do one later debounced pass from the stable state.
		if self.silentRefreshAgain then
			self.silentRefreshAgain = nil
			self.transmogRefreshTimer = self:ScheduleTimer(function()
				self.transmogRefreshTimer = nil
				self:Show("silent", true)
			end, 3)
		end
	end

	if self.backgroundScanInProgress then
		self:FinishBackgroundScan(mode)
	end

	-- If this call temporarily switched to the silent background build state,
	-- publish it only when complete; otherwise restore the last committed UI
	-- state.
	self:ExitSilentBuildState(enteredSilentBuildState, not self.silentRefreshInProgress)
end

function WQA:link(x)
	if not x then
		return ""
	end
	local t = string.upper(x.type)
	if t == "ACHIEVEMENT" then
		return GetAchievementLink(x.id)
	elseif t == "ITEM" then
		return select(2, GetItemInfo(x.id))
	else
		return ""
	end
end
 
function WQA:GetRewardForID(questID, key, type)
	local l
	if type == "MISSION" then
		l = self.missionList[questID].reward
	else
		l = self.questList[questID].reward
	end
 
	local r = ""
	if l then
		if l.item then
			if l.item then
				if l.item.transmog then
					r = r .. l.item.transmog
				end
				if l.item.itemLevelUpgrade then
					if r ~= "" then
						r = r .. " "
					end
					r = r .. "|cFF00FF00+" .. l.item.itemLevelUpgrade .. " iLvl|r"
				end
				if l.item.itemPercentUpgrade then
					if r ~= "" then
						r = r .. ", "
					end
					r = r .. "|cFF00FF00+" .. l.item.itemPercentUpgrade .. "%|r"
				end
				if l.item.AzeriteArmorCache then
					for i = 1, 5, 2 do
						local upgrade = l.item.AzeriteArmorCache[i]
						if upgrade > 0 then
							r = r .. "|cFF00FF00+" .. upgrade .. " iLvl|r"
						elseif upgrade < 0 then
							r = r .. "|cFFFF0000" .. upgrade .. " iLvl|r"
						else
							r = r .. "±" .. upgrade
						end
						if i ~= 5 then
							r = r .. " / "
						end
					end
				end
				if l.item.cache then
					local cache = l.item.cache
					local upgradeChance = cache.upgradeNum / cache.n
					upgradeChance = 1 / 2 * upgradeChance + .5
					upgradeChance = string.format("%X", (1 - upgradeChance) * 255)
					if string.len(upgradeChance) == 1 then
						upgradeChance = "0" .. upgradeChance
					end
					r =
						r ..
						"|cFF" ..
						upgradeChance ..
						"FF" ..
						upgradeChance .. cache.upgradeNum .. "/" .. cache.n .. " max +" .. cache.upgradeMax .. "|r"
				end
			end
			r = l.item.itemLink .. " " .. r
		end
		if l.currency and key ~= "item" then
			r = r .. l.currency.amount .. " " .. l.currency.name
		end
	end
	return r
end
 
function WQA:AnnounceChat(tasks, silent)
	if self.db.profile.options.chat == false then
		return
	end
	if next(tasks) == nil then
		if silent ~= true then
			print(L["NO_QUESTS"])
		end
		return
	end
 
	local output = L["WQChat"]
	print(output)
	local expansion, zoneID
	for _, task in ipairs(tasks) do
		local text, i = "", 0
 
		if self.db.profile.options.chatShowExpansion == true then
			if self:GetExpansion(task) ~= expansion then
				expansion = self:GetExpansion(task)
				print(self:GetExpansionName(expansion))
			end
		end
 
		if self.db.profile.options.chatShowZone == true then
			if self:GetTaskZoneID(task) ~= zoneID then
				zoneID = self:GetTaskZoneID(task)
				print(self:GetTaskZoneName(task))
			end
		end
 
		local l
		if task.type == "WORLD_QUEST" then
			l = self.questList[task.id]
		elseif task.type == "MISSION" then
			l = self.missionList[task.id]
		elseif task.type == "AREA_POI" then
			l = self.Criterias.AreaPoi.list[task.id][task.mapId]
		end
 
		local rewards = l.reward
 
		local more
		for k, v in pairs(rewards) do
			local rewardText = self:GetRewardTextByID(task.id, k, v, 1, task.type)
			if k == "achievement" or k == "chance" or k == "azeriteTraits" then
				for j = 2, 3 do
					local t = self:GetRewardTextByID(task.id, k, v, j, task.type)
					if t then
						rewardText = rewardText .. " & " .. t
					end
				end
				if self:GetRewardTextByID(task.id, k, v, 4, task.type) then
					more = true
				end
			end
 
			i = i + 1
			if i > 1 then
				text = text .. " & " .. rewardText
			else
				text = rewardText
			end
		end
		if more == true then
			text = text .. " & ..."
		end
 
		local taskTime = self:GetTaskTime(task)
		if self.db.profile.options.chatShowTime and taskTime and taskTime > 0 then
			output = "   " ..
				string.format(L["WQforAchTime"], self:GetTaskLink(task), self:formatTime(taskTime), text)
		else
			output = "   " .. string.format(L["WQforAch"], self:GetTaskLink(task), text)
		end
 
		print(output)
	end
end
 
local inspectScantip = CreateFrame("GameTooltip", "WorldQuestListInspectScanningTooltip", nil, "GameTooltipTemplate")
inspectScantip:SetOwner(UIParent, "ANCHOR_NONE")
 
local EquipLocToSlot1 = {
	INVTYPE_HEAD = 1,
	INVTYPE_NECK = 2,
	INVTYPE_SHOULDER = 3,
	INVTYPE_BODY = 4,
	INVTYPE_CHEST = 5,
	INVTYPE_ROBE = 5,
	INVTYPE_WAIST = 6,
	INVTYPE_LEGS = 7,
	INVTYPE_FEET = 8,
	INVTYPE_WRIST = 9,
	INVTYPE_HAND = 10,
	INVTYPE_FINGER = 11,
	INVTYPE_TRINKET = 13,
	INVTYPE_CLOAK = 15,
	INVTYPE_WEAPON = 16,
	INVTYPE_SHIELD = 17,
	INVTYPE_2HWEAPON = 16,
	INVTYPE_WEAPONMAINHAND = 16,
	INVTYPE_RANGED = 16,
	INVTYPE_RANGEDRIGHT = 16,
	INVTYPE_WEAPONOFFHAND = 17,
	INVTYPE_HOLDABLE = 17,
	INVTYPE_TABARD = 19
}
local EquipLocToSlot2 = {
	INVTYPE_FINGER = 12,
	INVTYPE_TRINKET = 14,
	INVTYPE_WEAPON = 17
}
 
local ReputationItemList = {
	-- Army of the Light Insignia
	[152957] = 2165,
	[152955] = 2165,
	[152956] = 2165,
	[152958] = 2165,
	[152960] = 2170,
	-- Argussian Reach Insignia
	[152954] = 2170,
	[152959] = 2170,
	[152961] = 2170,
	[141342] = 1894,
	-- The Wardens
	[139025] = 1894,
	[141991] = 1894,
	[147415] = 1894,
	[150929] = 1894,
	[146945] = 1894,
	[146939] = 1894,
	[141340] = 1900,
	-- Court of Farondis
	[139023] = 1900,
	[147410] = 1900,
	[141989] = 1900,
	[150927] = 1900,
	[146937] = 1900,
	[146943] = 1900,
	[139021] = 1883,
	-- Dreamweavers
	[141988] = 1883,
	[147411] = 1883,
	[141339] = 1883,
	[150926] = 1883,
	[146942] = 1883,
	[146936] = 1883,
	-- Highmountain Tribe
	[141341] = 1828,
	[139024] = 1828,
	[141990] = 1828,
	[147412] = 1828,
	[150928] = 1828,
	[146944] = 1828,
	[146938] = 1828,
	-- Valarjar
	[139020] = 1948,
	[141338] = 1948,
	[141987] = 1948,
	[147414] = 1948,
	[146935] = 1948,
	[146941] = 1948,
	[150925] = 1948,
	-- The Nightfallen
	[141343] = 1859,
	[141992] = 1859,
	[139026] = 1859,
	[147413] = 1859,
	[150930] = 1859,
	[146940] = 1859,
	[146946] = 1859
}
 
local ReputationCurrencyList = {
	[1579] = 2164, -- Champions of Azeroth
	[1598] = 2163, -- Tortollan Seekers
	[1593] = 2160, -- Proudmoore Admiralty
	[1592] = 2161, -- Order of Embers
	[1594] = 2162, -- Storm's Wake
	[1599] = 2159, -- 7th Legion
	[1597] = 2103, -- Zandalari Empire
	[1595] = 2156, -- Talanji's Expedition
	[1596] = 2158, -- Voldunai
	[1600] = 2157, -- The Honorbound
	[1742] = 2391, -- Rustbolt Resistance
	[1739] = 2400, -- Waveblade Ankoan
	[1757] = 2417, -- Uldum Accord
	[1758] = 2415, -- Rajani
	[1738] = 2373, -- The Unshackled
	[1807] = 2413, -- Court of Harvesters
	[1907] = 2470, -- Death's Advance
	[1804] = 2407, -- The Ascended
	[1982] = 2478, -- The Enlightened
	[1805] = 2410, -- The Undying Army
	[1806] = 2465, -- The Wild Hunt
	[1880] = 2432, -- Ve'nari
	[2819] = 2615, -- Azerothian Archives
	[2031] = 2507, -- Dragonscale Expedition
	[2652] = 2574, -- Dream Wardens
	[2109] = 2511, -- Iskaara Tuskarr
	[2420] = 2564, -- Loamm Niffen
	[2108] = 2503, -- Maruuk Centaur
	[2106] = 2510, -- Valdrakken Accord
	[2902] = 2594, -- The Assembly of the Deeps
	[2899] = 2570, -- Hallowfall Arathi
	[2903] = 2600, -- The Severed Threads
	[2897] = 2590 -- Council of Dornogal
}
 
-- Quests to skip reward data preload due to inaccurate or misleading Blizzard API results
local SkipRewardDataPreloadQuests = {
	[83366] = true, -- See issue #184
	-- Neighborhood weekly quests
	[95413] = true,
	[95416] = true,
	[95440] = true,
	[95438] = true
}
 
local REWARD_PRELOAD_INTERVAL = 0.35
local REWARD_PRELOAD_RETRY_COOLDOWN = 5
local REWARD_INTERACTION_RETRY = 1

-- Pace the full cross-expansion world-quest discovery pass as well. Querying
-- every map and reward in one uninterrupted burst can interfere with Blizzard's
-- normal quest-giver interaction.
local REWARD_SCAN_MAP_INTERVAL = 0.03
local REWARD_SCAN_QUEST_INTERVAL = 0.02
local REWARD_SCAN_QUEST_BATCH_SIZE = 10
local REWARD_SCAN_INTERACTION_RETRY = 0.25
local REWARD_SCAN_SAFE_WINDOW_RETRY = 0.50

-- Full refresh consistency safeguards.
local FULL_SCAN_MAP_RETRY_LIMIT = 3
local FULL_SCAN_MAP_RETRY_DELAY = 0.50
local FULL_SCAN_REWARD_TIMEOUT = 15

function WQA:IsQuestInteractionActive()
	if QuestFrame and QuestFrame.IsShown and QuestFrame:IsShown() then
		return true
	end
	if GossipFrame and GossipFrame.IsShown and GossipFrame:IsShown() then
		return true
	end
	if self:IsQuestLogDetailActive() then
		return true
	end
	return false
end

function WQA:StopRewardPreloadQueue()
	if self.rewardPreloadTimer then
		self:CancelTimer(self.rewardPreloadTimer)
		self.rewardPreloadTimer = nil
	end
	self.rewardPreloadQueue = {}
	self.rewardPreloadQueued = {}
	self.rewardPreloadForce = {}
end
function WQA:ResetRewardPreloadQueue()
	self:StopRewardPreloadQueue()
	if self.rewardPendingPollTimer then
		self:CancelTimer(self.rewardPendingPollTimer)
		self.rewardPendingPollTimer = nil
	end
	self.rewardPreloadLastRequest = self.rewardPreloadLastRequest or {}
	self.rewardPreloadRequestsThisScan = 0
	self.rewardPreloadPausedForQuestUI = false
end

function WQA:SchedulePendingRewardCheck(delay)
	if self.rewardPendingPollTimer then
		return
	end
	self.rewardPendingPollTimer = self:ScheduleTimer(function()
		self.rewardPendingPollTimer = nil
		self:ProcessPendingRewards()
	end, delay or 1)
end

function WQA:StartRewardPreloadQueue(delay)
	if self.rewardPreloadTimer then
		return
	end
	if not self.rewardPreloadQueue or #self.rewardPreloadQueue == 0 then
		return
	end
	self.rewardPreloadTimer = self:ScheduleTimer(function()
		self.rewardPreloadTimer = nil
		self:ProcessRewardPreloadQueue()
	end, delay or 0.1)
end

function WQA:QueueRewardPreload(questID, force)
	if not questID or SkipRewardDataPreloadQuests[questID] then
		return
	end
	if not HaveQuestData(questID) then
		return
	end
	if HaveQuestRewardData(questID) and not force then
		return
	end

	self.rewardPreloadQueue = self.rewardPreloadQueue or {}
	self.rewardPreloadQueued = self.rewardPreloadQueued or {}
	self.rewardPreloadForce = self.rewardPreloadForce or {}
	self.rewardPreloadLastRequest = self.rewardPreloadLastRequest or {}

	if self.rewardPreloadQueued[questID] then
		if force then
			self.rewardPreloadForce[questID] = true
		end
		return
	end

	local now = GetTime and GetTime() or 0
	local lastRequest = self.rewardPreloadLastRequest[questID]
	if lastRequest and now - lastRequest < REWARD_PRELOAD_RETRY_COOLDOWN then
		return
	end

	self.rewardPreloadQueued[questID] = true
	if force then
		self.rewardPreloadForce[questID] = true
	end
	table.insert(self.rewardPreloadQueue, questID)
	self:StartRewardPreloadQueue()
end
function WQA:ProcessRewardPreloadQueue()
	if not self.rewardPreloadQueue or #self.rewardPreloadQueue == 0 then
		return
	end
	if not self:IsSafeWorldQuestDiscoveryWindow() then
		self.rewardPreloadPausedForSafeWindow = true
		return
	end
	self.rewardPreloadPausedForSafeWindow = false

	if self:IsQuestInteractionActive() then
		self.rewardPreloadPausedForQuestUI = true
		self:StartRewardPreloadQueue(REWARD_INTERACTION_RETRY)
		return
	end
	self.rewardPreloadPausedForQuestUI = false

	local questID = table.remove(self.rewardPreloadQueue, 1)
	local force = self.rewardPreloadForce and self.rewardPreloadForce[questID] == true
	if self.rewardPreloadQueued then
		self.rewardPreloadQueued[questID] = nil
	end
	if self.rewardPreloadForce then
		self.rewardPreloadForce[questID] = nil
	end

	if HaveQuestData(questID)
		and (force or not HaveQuestRewardData(questID))
		and not SkipRewardDataPreloadQuests[questID]
	then
		C_TaskQuest.RequestPreloadRewardData(questID)
		self.rewardPreloadLastRequest = self.rewardPreloadLastRequest or {}
		self.rewardPreloadLastRequest[questID] = GetTime and GetTime() or 0
		self.rewardPreloadRequestsThisScan = (self.rewardPreloadRequestsThisScan or 0) + 1
		self:Debug(
			force and "Forced reward preload request" or "Reward preload request",
			questID,
			"queue remaining=" .. tostring(#self.rewardPreloadQueue)
		)
	end

	if #self.rewardPreloadQueue > 0 then
		self:StartRewardPreloadQueue(REWARD_PRELOAD_INTERVAL)
	end
end
function WQA:CountTableEntries(tbl)
	local count = 0
	for _ in pairs(tbl or {}) do
		count = count + 1
	end
	return count
end

function WQA:IsFullRefreshSnapshotComplete()
	local unresolvedMaps = self:CountTableEntries(self.rewardScanUnresolvedMaps)
	local unresolvedRewards = self:CountTableEntries(self.rewardScanUnresolvedRewardQuests)
	local pendingRewards = self:CountTableEntries(self.pendingQuests)

	return unresolvedMaps == 0
		and unresolvedRewards == 0
		and pendingRewards == 0
		and self.rewards == true
		and self.emissaryRewards == true,
		unresolvedMaps,
		unresolvedRewards,
		pendingRewards
end

function WQA:AbortIncompleteFullRefresh(unresolvedMaps, unresolvedRewards, pendingRewards)
	if self.rewardScanTimer then
		self:CancelTimer(self.rewardScanTimer)
		self.rewardScanTimer = nil
	end
	if self.rewardPendingPollTimer then
		self:CancelTimer(self.rewardPendingPollTimer)
		self.rewardPendingPollTimer = nil
	end

	self.event:UnregisterEvent("QUEST_LOG_UPDATE")
	self.event:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
	self.event:UnregisterEvent("QUEST_FINISHED")
	self.event:UnregisterEvent("GOSSIP_CLOSED")
	self:StopRewardPreloadQueue()

	if self.backgroundScanCommittedState then
		self:ApplyQuestRefreshState(self.backgroundScanCommittedState)
	end

	self.rewardScanInProgress = false
	self.rewardScanCurrentQuests = nil
	self.rewardScanCurrentMapID = nil
	self.rewardScanQuestIndex = nil
	self.backgroundScanInProgress = false
	self.backgroundScanMode = nil
	self.backgroundScanQueuedMode = nil
	self.backgroundScanCommittedState = nil
	self.fullRefreshExplicitlyRequested = false
	self.pendingSafeDiscoveryMode = nil
	self.rewardContinuationMode = nil

	self:RefreshVisibleTaskList()
	self:UpdateLDBText(next(self.activeTasks or {}), next(self.newTasks or {}))

	print(
		"|cff33ff99WQAW:|r Full refresh incomplete. Blizzard data was unavailable "
			.. "(maps: " .. tostring(unresolvedMaps)
			.. ", rewards: " .. tostring(unresolvedRewards)
			.. ", pending: " .. tostring(pendingRewards)
			.. "). Previous list retained."
	)
end

function WQA:ProcessPendingRewards()
	if not self:IsSafeWorldQuestDiscoveryWindow() then
		self.rewardPendingPausedForSafeWindow = true
		return
	end
	self.rewardPendingPausedForSafeWindow = false
	self.rewardPreloadPausedForSafeWindow = false

	if self:IsQuestInteractionActive() then
		self.rewardPreloadPausedForQuestUI = true
		self:SchedulePendingRewardCheck(REWARD_SCAN_INTERACTION_RETRY)
		return
	end

	self.rewardPreloadPausedForQuestUI = false
	if self.rewardPendingPollTimer then
		self:CancelTimer(self.rewardPendingPollTimer)
		self.rewardPendingPollTimer = nil
	end

	local enteredSilentBuildState = self:EnterSilentBuildState()
	local retry = false
	local now = GetTime and GetTime() or 0

	self.rewardScanRewardPendingSince = self.rewardScanRewardPendingSince or {}
	self.rewardScanUnresolvedRewardQuests = self.rewardScanUnresolvedRewardQuests or {}

	for questID, _ in pairs(self.pendingQuests or {}) do
		local isEmissary = self.questList[questID] and self.questList[questID].isEmissary
		local questNeedsRetry = false

		if HaveQuestData(questID) and HaveQuestRewardData(questID) then
			questNeedsRetry = self:CheckItems(questID, isEmissary)
			if self:CheckCurrencies(questID, isEmissary) then
				questNeedsRetry = true
			end
		else
			self:QueueRewardPreload(questID)
			questNeedsRetry = true
		end

		if not questNeedsRetry then
			self.pendingQuests[questID] = nil
			self.rewardScanRewardPendingSince[questID] = nil
		else
			local firstPending = self.rewardScanRewardPendingSince[questID]
			if not firstPending then
				firstPending = now
				self.rewardScanRewardPendingSince[questID] = firstPending
			end

			if now - firstPending >= FULL_SCAN_REWARD_TIMEOUT then
				self.rewardScanUnresolvedRewardQuests[questID] = true
				self.pendingQuests[questID] = nil
				self:Debug("Reward data unresolved after timeout", questID)
			else
				retry = true
			end
		end
	end

	if retry then
		self.event:RegisterEvent("QUEST_LOG_UPDATE")
		self.event:RegisterEvent("GET_ITEM_INFO_RECEIVED")
		self:StartRewardPreloadQueue()
		self:SchedulePendingRewardCheck(1)
	else
		self:StopRewardPreloadQueue()
		self.rewards = true
		self.emissaryRewards = true

		local callbackMode =
			self.pendingRefreshMode
			or self.backgroundScanMode
			or self.rewardContinuationMode
			or self.lastMode

		if callbackMode then
			self:CheckWQ(callbackMode)
		end
	end

	self:ExitSilentBuildState(enteredSilentBuildState, not self.silentRefreshInProgress)
end

function WQA:ProcessRewardQuest(mapID, questID)
	local questTagInfo = GetQuestTagInfo(questID)
	local worldQuestType = 0
	if questTagInfo then
		worldQuestType = questTagInfo.worldQuestType
	end

	if self.questList[questID] and not self.db.profile.options.reward.general.worldQuestType[worldQuestType] then
		self.questList[questID] = nil
	end

	local questZoneID = C_TaskQuest.GetQuestZoneID(questID)
	if
		self.db.profile.options.zone[questZoneID] == true and
		self.db.profile.options.reward.general.worldQuestType[worldQuestType]
	then
		if QuestUtils_IsQuestWorldQuest(questID) and not self.db.global.completed[questID] then
			local exp = 0
			for expansion, zones in pairs(WQA.ZoneIDList) do
				for _, zoneID in pairs(zones) do
					if questZoneID == zoneID then
						exp = expansion
					end
				end
			end

			if
				self.db.profile.achievements[11189] ~= "disabled" and not select(4, GetAchievementInfo(11189)) and exp == 7 and
				mapID ~= 830 and
				mapID ~= 885 and
				mapID ~= 882
			then
				self:AddRewardToQuest(questID, "ACHIEVEMENT", 11189)
			elseif
				self.db.profile.achievements[13144] ~= "disabled" and not select(4, GetAchievementInfo(13144)) and exp == 8
			then
				self:AddRewardToQuest(questID, "ACHIEVEMENT", 13144)
			elseif
				self.db.profile.achievements[14758] ~= "disabled" and not select(4, GetAchievementInfo(14758)) and exp == 9
			then
				self:AddRewardToQuest(questID, "ACHIEVEMENT", 14758)
			end
		end

		local questNeedsRetry = false
		if not SkipRewardDataPreloadQuests[questID] and HaveQuestData(questID) and not HaveQuestRewardData(questID) then
			self:QueueRewardPreload(questID)
			questNeedsRetry = true
		end

		if self:CheckItems(questID) then
			questNeedsRetry = true
		end
		if self:CheckCurrencies(questID) then
			questNeedsRetry = true
		end

		if questNeedsRetry then
			self.rewardScanRetry = true
			self.pendingQuests[questID] = true
		end

		if self.questList[questID] then
			self.questList[questID].scanMapID = mapID
		end

		local tradeskillLineID = questTagInfo and questTagInfo.tradeskillLineID
		if tradeskillLineID then
			local professionName = C_TradeSkillUI.GetTradeSkillDisplayName(tradeskillLineID)
			local exp = 0
			for expansion, zones in pairs(WQA.ZoneIDList) do
				for _, zoneID in pairs(zones) do
					if questZoneID == zoneID then
						exp = expansion
					end
				end
			end

			if
				exp > 0 and
				self.db.char[exp] and
				self.db.char[exp].profession and
				self.db.char[exp].profession[tradeskillLineID] and
				self.db.profile.options.reward[exp] and
				self.db.profile.options.reward[exp].profession and
				self.db.profile.options.reward[exp].profession[tradeskillLineID] and
				not self.db.char[exp].profession[tradeskillLineID].isMaxLevel and
				self.db.profile.options.reward[exp].profession[tradeskillLineID].skillup
			then
				self:AddRewardToQuest(questID, "PROFESSION_SKILLUP", professionName)
			end
		end

		-- Stamp after every reward category (including profession-only quests).
		if self.questList[questID] then
			self.questList[questID].scanMapID = mapID
			self.questList[questID].rawItemRewardCount =
				self.rewardScanRawItemRewardCounts and self.rewardScanRawItemRewardCounts[questID] or nil
			self.questList[questID].rawCurrencyRewardCount =
				self.rewardScanRawCurrencyRewardCounts and self.rewardScanRawCurrencyRewardCounts[questID] or nil
			self.questList[questID].rawGoldRewardMoney =
				self.rewardScanRawGoldRewardMoney and self.rewardScanRawGoldRewardMoney[questID] or nil
		end
	end
end

function WQA:ScheduleRewardScanStep(delay)
	if self.rewardScanTimer then
		return
	end

	self.rewardScanTimer = self:ScheduleTimer(function()
		self.rewardScanTimer = nil
		self:ProcessRewardScanStep()
	end, delay or REWARD_SCAN_QUEST_INTERVAL)
end

function WQA:FinishRewardDiscoveryScan()
	self.rewardScanInProgress = false
	self.rewardScanCurrentQuests = nil
	self.rewardScanCurrentMapID = nil
	self.rewardScanQuestIndex = nil

	if self.rewardScanRetry == true then
		self:Debug("|cFFFF0000<<<SOME ITEMS PENDING - PACED QUEUE>>>|r")
		self.event:RegisterEvent("QUEST_LOG_UPDATE")
		self.event:RegisterEvent("GET_ITEM_INFO_RECEIVED")
		self:StartRewardPreloadQueue()
		self:SchedulePendingRewardCheck(1)
	else
		self.rewards = true
	end

	-- Avoid overlapping the old emissary scan with map discovery. Suppress its
	-- legacy immediate CheckWQ callback here so this finalizer publishes exactly
	-- one snapshot.
	self.rewardDiscoveryFinalizing = true
	self:EmissaryReward()
	self.rewardDiscoveryFinalizing = false

	-- Full refreshes are transactional. If reward/item data is still pending,
	-- CheckWQ keeps the previous committed list visible and waits for
	-- ProcessPendingRewards() instead of publishing a partial snapshot.
	self:CheckWQ(self.backgroundScanMode or self.pendingRefreshMode or self.rewardContinuationMode or self.lastMode)
end

function WQA:ProcessRewardScanStep()
	if not self.rewardScanInProgress then
		return
	end

	if not self:IsSafeWorldQuestDiscoveryWindow() then
		self.rewardScanPausedForSafeWindow = true
		return
	end
	self.rewardScanPausedForSafeWindow = false

	if self:IsQuestInteractionActive() then
		self.rewardScanPausedForQuestUI = true
		self:ScheduleRewardScanStep(REWARD_SCAN_INTERACTION_RETRY)
		return
	end
	self.rewardScanPausedForQuestUI = false

	local enteredSilentBuildState = self:EnterSilentBuildState()

	if self.rewardScanCurrentQuests then
		local processedThisTick = 0

		while processedThisTick < REWARD_SCAN_QUEST_BATCH_SIZE do
			local quest = self.rewardScanCurrentQuests[self.rewardScanQuestIndex]
			if not quest then
				break
			end

			self:ProcessRewardQuest(self.rewardScanCurrentMapID, quest.questID)
			self.rewardScanQuestIndex = self.rewardScanQuestIndex + 1
			self.rewardScanQuestsProcessed = (self.rewardScanQuestsProcessed or 0) + 1
			processedThisTick = processedThisTick + 1
		end

		if self.rewardScanCurrentQuests[self.rewardScanQuestIndex] then
			self:ExitSilentBuildState(enteredSilentBuildState, false)
			self:ScheduleRewardScanStep(REWARD_SCAN_QUEST_INTERVAL)
			return
		end

		self.rewardScanCurrentQuests = nil
		self.rewardScanCurrentMapID = nil
		self.rewardScanQuestIndex = nil
	end

	local mapID = self.rewardScanMaps and self.rewardScanMaps[self.rewardScanMapIndex]
	if mapID then
		local quests = C_TaskQuest.GetQuestsOnMap(mapID)
		local accumulated = self.rewardScanMapAccumulatedQuests[mapID] or {}
		self.rewardScanMapAccumulatedQuests[mapID] = accumulated

		if quests then
			for _, quest in ipairs(quests) do
				if quest and quest.questID then
					accumulated[quest.questID] = quest
				end
			end
		end

		local previous = self.rewardScanPreviousActiveQuestsByMap[mapID]
		local missingPrevious = 0
		if previous then
			for questID in pairs(previous) do
				if not accumulated[questID] then
					missingPrevious = missingPrevious + 1
				end
			end
		end

		local suspicious = missingPrevious > 0
		if suspicious then
			local attempts = (self.rewardScanMapRetryCounts[mapID] or 0) + 1
			self.rewardScanMapRetryCounts[mapID] = attempts
			self.rewardScanMapRetries = (self.rewardScanMapRetries or 0) + 1

			self:Debug(
				"Retrying map quest data",
				mapID,
				"attempt=" .. tostring(attempts),
				"nil=" .. tostring(quests == nil),
				"missingPrevious=" .. tostring(missingPrevious)
			)

			if attempts < FULL_SCAN_MAP_RETRY_LIMIT then
				self:ExitSilentBuildState(enteredSilentBuildState, false)
				self:ScheduleRewardScanStep(FULL_SCAN_MAP_RETRY_DELAY)
				return
			end

			if missingPrevious > 0 then
				self.rewardScanUnresolvedMaps[mapID] = true
				self:Debug("Map still missing previously active quests after retries", mapID)
			end
		end

		local acceptedQuests = {}
		for _, quest in pairs(accumulated) do
			table.insert(acceptedQuests, quest)
		end

		self.rewardScanMapAccumulatedQuests[mapID] = nil
		self.rewardScanMapIndex = self.rewardScanMapIndex + 1
		self.rewardScanMapsProcessed = (self.rewardScanMapsProcessed or 0) + 1
		self.rewardScanCurrentMapID = mapID
		self.rewardScanCurrentQuests = acceptedQuests
		self.rewardScanQuestIndex = 1

		self:ExitSilentBuildState(enteredSilentBuildState, false)

		if #self.rewardScanCurrentQuests > 0 then
			self:ScheduleRewardScanStep(REWARD_SCAN_QUEST_INTERVAL)
		else
			self.rewardScanCurrentQuests = nil
			self.rewardScanCurrentMapID = nil
			self.rewardScanQuestIndex = nil
			self:ScheduleRewardScanStep(REWARD_SCAN_MAP_INTERVAL)
		end
		return
	end

	self:FinishRewardDiscoveryScan()
	self:ExitSilentBuildState(enteredSilentBuildState, not self.silentRefreshInProgress)
end

function WQA:Reward()
	self:Debug("Reward - starting cooperative discovery scan")

	self.event:UnregisterEvent("QUEST_LOG_UPDATE")
	self.event:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
	self:ResetRewardPreloadQueue()
	self.rewards = false

	if self.rewardScanTimer then
		self:CancelTimer(self.rewardScanTimer)
		self.rewardScanTimer = nil
	end

	if self.db.profile.options.reward.gear.azeriteTraits ~= "" then
		self.azeriteTraitsList = {}
		for spellID in string.gmatch(self.db.profile.options.reward.gear.azeriteTraits, "(%d+)") do
			self.azeriteTraitsList[tonumber(spellID)] = true
		end
	end

	self.rewardScanMaps = {}
	for expansionID in pairs(self.ZoneIDList) do
		for _, mapID in pairs(self.ZoneIDList[expansionID]) do
			if self.db.profile.options.zone[mapID] == true then
				table.insert(self.rewardScanMaps, mapID)
			end
		end
	end
	table.sort(self.rewardScanMaps)

	self.rewardScanMapIndex = 1
	self.rewardScanCurrentMapID = nil
	self.rewardScanCurrentQuests = nil
	self.rewardScanQuestIndex = nil
	self.rewardScanRetry = false
	self.rewardScanInProgress = true
	self.rewardScanMapsProcessed = 0
	self.rewardScanQuestsProcessed = 0
	self.rewardScanPausedForQuestUI = false
	self.rewardScanMapRetryCounts = {}
	self.rewardScanMapRetries = 0
	self.rewardScanUnresolvedMaps = {}
	self.rewardScanMapAccumulatedQuests = {}
	self.rewardScanRewardPendingSince = {}
	self.rewardScanUnresolvedRewardQuests = {}
	self.rewardScanPreviousActiveQuestsByMap = {}
	self.rewardScanRawItemRewardCounts = {}
	self.rewardScanRawCurrencyRewardCounts = {}
	self.rewardScanRawGoldRewardMoney = {}

	local previousState = self.backgroundScanCommittedState
	local now = GetServerTime and GetServerTime() or time()
	if previousState and type(previousState.activeTasks) == "table" then
		for _, task in ipairs(previousState.activeTasks) do
			if task.type == "WORLD_QUEST"
				and (not task.expiresAt or task.expiresAt > now)
			then
				local previousQuest = previousState.questList and previousState.questList[task.id]
				local mapID =
					task.mapId
					or (previousQuest and previousQuest.scanMapID)
					or C_TaskQuest.GetQuestZoneID(task.id)
				if mapID then
					self.rewardScanPreviousActiveQuestsByMap[mapID] =
						self.rewardScanPreviousActiveQuestsByMap[mapID] or {}
					self.rewardScanPreviousActiveQuestsByMap[mapID][task.id] = true
				end
			end
		end
	end

	self:Debug("Reward discovery maps queued", #self.rewardScanMaps)
	self:ScheduleRewardScanStep(0.1)
end

local weaponCache = {
	[165872] = true, -- 7th Legion Equipment Cache
	[165867] = true, -- Kul Tiran Weapons Cache
	[165871] = true, -- Honorbound Equipment Cache
	[165863] = true -- Zandalari Weapons Cache
}
local armorCache = {
	[165872] = true, -- 7th Legion Equipment Cache
	[165870] = true, -- Order of Embers Equipment Cache
	[165868] = true, -- Storm's Wake Equipment Cache
	[165869] = true, -- Proudmoore Admiralty Equipment Cache
	[165871] = true, -- Honorbound Equipment Cache
	[165865] = true, -- Nazmir Expeditionary Equipment Cache
	[165864] = true, -- Voldunai Equipment Cache
	[165866] = true -- Zandalari Empire Equipment Cache
}
local jewelryCache = {
	[165785] = true -- Tortollan Trader's Stock
}
 
-- Optional transmog-addon integration
local function SearchAllTheThingsSafely(itemLink)
	if type(AllTheThings) ~= "table" or type(AllTheThings.SearchForLink) ~= "function" then
		return nil
	end

	-- All The Things is optional. Never allow an ATT error to interrupt WQAW.
	local ok, result = pcall(AllTheThings.SearchForLink, itemLink)
	if not ok then
		return nil
	end

	return result
end

-- CanIMogIt
function WQA:IsTransmogable(itemLink)
	-- Returns whether the item is transmoggable or not.
 
	-- White items are not transmoggable.
	local quality = select(3, C_Item.GetItemInfo(itemLink))
	if quality == nil then
		return
	end
	if quality <= 1 then
		return false
	end
 
	local itemID, _, _, slotName = C_Item.GetItemInfoInstant(itemLink)
 
	-- See if the game considers it transmoggable
	local transmoggable = select(3, C_TransmogCollection.GetItemInfo(itemID))
	if transmoggable == false then
		return false
	end
 
	-- See if the item is in a valid transmoggable slot
	local slot = EquipLocToSlot1[slotName]
	if slot == nil or slot == 11 or slot == 13 or slot == 2 then
		return false
	end
	return true
end
 
function WQA:EvaluateTransmogReward(itemLink)
	local transmog
	local reason
	local searchForLinkResult = SearchAllTheThingsSafely(itemLink)
	if searchForLinkResult and searchForLinkResult[1] then
		local state = searchForLinkResult[1].collected
		if not state then
			transmog = "|TInterface\\Addons\\AllTheThings\\assets\\unknown:0|t"
			reason = "appearance"
		elseif state == 2 and self.db.profile.options.reward.gear.unknownSource then
			transmog = "|TInterface\\Addons\\AllTheThings\\assets\\known_circle:0|t"
			reason = "source"
		end
	end

	if CanIMogIt and not transmog then
		if CanIMogIt:IsEquippable(itemLink) and CanIMogIt:CharacterCanLearnTransmog(itemLink) then
			if not CanIMogIt:PlayerKnowsTransmog(itemLink) then
				transmog = "|TInterface\\AddOns\\CanIMogIt\\Icons\\UNKNOWN:0|t"
				reason = "appearance"
			elseif not CanIMogIt:PlayerKnowsTransmogFromItem(itemLink) and self.db.profile.options.reward.gear.unknownSource then
				transmog = "|TInterface\\AddOns\\CanIMogIt\\Icons\\KNOWN_circle:0|t"
				reason = "source"
			end
		end
	end

	return transmog, reason
end

function WQA:TrackActiveTransmogReward(questID, itemLink, reason)
	local itemAppearanceID, itemModifiedAppearanceID = C_TransmogCollection.GetItemInfo(itemLink)

	if reason == "appearance" and itemAppearanceID then
		self.activeTransmogAppearanceIDs = self.activeTransmogAppearanceIDs or {}
		self.activeTransmogAppearanceQuestIDs = self.activeTransmogAppearanceQuestIDs or {}
		self.activeTransmogAppearanceIDs[itemAppearanceID] = true
		self.activeTransmogAppearanceQuestIDs[itemAppearanceID] = self.activeTransmogAppearanceQuestIDs[itemAppearanceID] or {}
		self.activeTransmogAppearanceQuestIDs[itemAppearanceID][questID] = true
	end

	if itemModifiedAppearanceID then
		self.activeTransmogSourceIDs = self.activeTransmogSourceIDs or {}
		self.activeTransmogSourceQuestIDs = self.activeTransmogSourceQuestIDs or {}
		self.activeTransmogSourceIDs[itemModifiedAppearanceID] = true
		self.activeTransmogSourceQuestIDs[itemModifiedAppearanceID] = self.activeTransmogSourceQuestIDs[itemModifiedAppearanceID] or {}
		self.activeTransmogSourceQuestIDs[itemModifiedAppearanceID][questID] = true
	end
end

function WQA:GetAppearanceIDForTransmogSource(itemModifiedAppearanceID)
	if not itemModifiedAppearanceID then
		return nil
	end
	if C_TransmogCollection.GetAppearanceSourceInfo then
		local ok, info = pcall(C_TransmogCollection.GetAppearanceSourceInfo, itemModifiedAppearanceID)
		if ok and info and info.itemAppearanceID then
			return info.itemAppearanceID
		end
	end
	if C_TransmogCollection.GetSourceInfo then
		local ok, info = pcall(C_TransmogCollection.GetSourceInfo, itemModifiedAppearanceID)
		if ok and info then
			return info.visualID
		end
	end
	return nil
end

local function MergeQuestIDSet(target, sourceSet)
	if type(sourceSet) ~= "table" then
		return target
	end
	target = target or {}
	for questID in pairs(sourceSet) do
		target[questID] = true
	end
	return target
end

function WQA:GetTrackedTransmogQuestIDsForSource(itemModifiedAppearanceID)
	local quests = {}
	quests = MergeQuestIDSet(quests, self.activeTransmogSourceQuestIDs and self.activeTransmogSourceQuestIDs[itemModifiedAppearanceID])
	local appearanceID = self:GetAppearanceIDForTransmogSource(itemModifiedAppearanceID)
	if appearanceID then
		quests = MergeQuestIDSet(quests, self.activeTransmogAppearanceQuestIDs and self.activeTransmogAppearanceQuestIDs[appearanceID])
	end
	return quests
end

function WQA:IsTrackedTransmogSourceRelevant(itemModifiedAppearanceID)
	return next(self:GetTrackedTransmogQuestIDsForSource(itemModifiedAppearanceID)) ~= nil
end

function WQA:RemoveQuestFromTransmogTracking(questID)
	for appearanceID, questIDs in pairs(self.activeTransmogAppearanceQuestIDs or {}) do
		questIDs[questID] = nil
		if not next(questIDs) then
			self.activeTransmogAppearanceQuestIDs[appearanceID] = nil
			self.activeTransmogAppearanceIDs[appearanceID] = nil
		end
	end
	for sourceID, questIDs in pairs(self.activeTransmogSourceQuestIDs or {}) do
		questIDs[questID] = nil
		if not next(questIDs) then
			self.activeTransmogSourceQuestIDs[sourceID] = nil
			self.activeTransmogSourceIDs[sourceID] = nil
		end
	end
end

function WQA:RefreshTrackedTransmogQuests(questIDs)
	if type(questIDs) ~= "table" then
		return
	end

	local changed = false
	for questID in pairs(questIDs) do
		local quest = self.questList and self.questList[questID]
		local reward = quest and quest.reward
		local item = reward and reward.item
		if item and item.itemLink and item.transmog then
			local newTransmog, newReason = self:EvaluateTransmogReward(item.itemLink)
			self:RemoveQuestFromTransmogTracking(questID)

			if newTransmog then
				item.transmog = newTransmog
				self:TrackActiveTransmogReward(questID, item.itemLink, newReason)
			else
				item.transmog = nil
				local hasOtherItemReason = item.itemLevelUpgrade
					or item.itemPercentUpgrade
					or item.AzeriteArmorCache
					or item.cache
					or item._wqawOtherItemReason
				if not hasOtherItemReason then
					reward.item = nil
				end

				if not next(reward) then
					self.questList[questID] = nil
					RemoveWorldQuestFromTaskList(self.activeTasks, questID)
					RemoveWorldQuestFromTaskList(self.newTasks, questID)
				end
			end
			changed = true
		end
	end

	if changed then
		self.activeTasks = self:SortQuestList(self.activeTasks or {})
		self:UpdateLDBText(next(self.activeTasks or {}), next(self.newTasks or {}))
		self:RefreshVisibleTaskList()
		self:SavePersistentDisplayCache()
	end
end


function WQA:GetPreviousCommittedQuestData(questID)
	local state = self.backgroundScanCommittedState
	if not state or type(state.questList) ~= "table" then
		return nil
	end
	return state.questList[questID]
end

function WQA:PreviousCommittedQuestHadItemReward(questID)
	local previous = self:GetPreviousCommittedQuestData(questID)
	if not previous then
		return false
	end

	if type(previous.rawItemRewardCount) == "number" and previous.rawItemRewardCount > 0 then
		return true
	end

	local reward = previous.reward
	if type(reward) ~= "table" then
		return false
	end

	return reward.customItem ~= nil
		or reward.item ~= nil
		or reward.recipe ~= nil
		or reward.azeriteTraits ~= nil
end

function WQA:PreviousCommittedQuestHadCurrencyReward(questID)
	local previous = self:GetPreviousCommittedQuestData(questID)
	if not previous then
		return false
	end

	if type(previous.rawCurrencyRewardCount) == "number" and previous.rawCurrencyRewardCount > 0 then
		return true
	end

	return previous.reward and previous.reward.currency ~= nil
end

function WQA:PreviousCommittedQuestHadGoldReward(questID)
	local previous = self:GetPreviousCommittedQuestData(questID)
	if not previous then
		return false
	end

	if type(previous.rawGoldRewardMoney) == "number" and previous.rawGoldRewardMoney > 0 then
		return true
	end

	return previous.reward and previous.reward.gold ~= nil
end

function WQA:CheckItems(questID, isEmissary)
	local numQuestRewards = GetNumQuestLogRewards(questID) or 0
	self.rewardScanRawItemRewardCounts = self.rewardScanRawItemRewardCounts or {}
	self.rewardScanRawItemRewardCounts[questID] = numQuestRewards

	if numQuestRewards == 0 then
		if self.backgroundScanInProgress and self:PreviousCommittedQuestHadItemReward(questID) then
			self:Debug("Previously tracked item reward unexpectedly returned zero", questID)
			self:QueueRewardPreload(questID, true)
			return true
		end
		return false
	end

	local retryArray = {}
 
	for rewardIndex = 1, numQuestRewards do
		retryArray[rewardIndex] = self:CheckReward(questID, isEmissary, rewardIndex)
	end
 
	for _, retry in pairs(retryArray) do
		if retry then return true end
	end
 
	return false
end
 
function WQA:CheckReward(questID, isEmissary, rewardIndex)
	local retry = false
 
	local itemName, itemTexture, quantity, quality, isUsable, itemID = GetQuestLogRewardInfo(rewardIndex, questID)
	if itemID then
		inspectScantip:SetQuestLogItem("reward", rewardIndex, questID)
		local itemLink = select(2, inspectScantip:GetItem())
		if not itemLink then
			return true
		elseif string.find(itemLink, "%[]") then
			return true
		end
 
		local itemName,
		_,
		itemRarity,
		itemLevel,
		itemMinLevel,
		itemType,
		itemSubType,
		itemStackCount,
		itemEquipLoc,
		itemTexture,
		itemSellPrice,
		itemClassID,
		itemSubClassID = GetItemInfo(itemLink)
		local expacID = self:GetExpansionByQuestID(questID)
 
		-- Ask Pawn if this is an Upgrade
		if PawnIsItemAnUpgrade and self.db.profile.options.reward.gear.PawnUpgrade then
			local Item = PawnGetItemData(itemLink)
			if Item then
				local UpgradeInfo, BestItemFor, SecondBestItemFor, NeedsEnhancements = PawnIsItemAnUpgrade(Item)
				if
					UpgradeInfo and UpgradeInfo[1].PercentUpgrade * 100 >= self.db.profile.options.reward.gear.PercentUpgradeMin and
					UpgradeInfo[1].PercentUpgrade < 10
				then
					local item = {
						itemLink = itemLink,
						itemPercentUpgrade = math.floor(UpgradeInfo[1].PercentUpgrade * 100 + .5)
					}
					self:AddRewardToQuest(questID, "ITEM", item, isEmissary)
				end
			end
		end
 
		-- StatWeightScore
		local StatWeightScore = LibStub("AceAddon-3.0"):GetAddon("StatWeightScore", true)
		if StatWeightScore and self.db.profile.options.reward.gear.StatWeightScore then
			local slotID = EquipLocToSlot1[itemEquipLoc]
			if slotID then
				local itemPercentUpgrade = 0
				local ScoreModule = StatWeightScore:GetModule("StatWeightScoreScore")
				local SpecModule = StatWeightScore:GetModule("StatWeightScoreSpec")
				local ScanningTooltipModule = StatWeightScore:GetModule("StatWeightScoreScanningTooltip")
				local specs = SpecModule:GetSpecs()
				for _, spec in pairs(specs) do
					if spec.Enabled then
						local score =
							ScoreModule:CalculateItemScore(
								itemLink,
								slotID,
								ScanningTooltipModule:ScanTooltip(itemLink),
								spec,
								equippedItemHasUniqueGem
							).Score
						local equippedScore
						local equippedLink = GetInventoryItemLink("player", slotID)
						if equippedLink then
							equippedScore =
								ScoreModule:CalculateItemScore(
									equippedLink,
									slotID,
									ScanningTooltipModule:ScanTooltip(equippedLink),
									spec,
									equippedItemHasUniqueGem
								).Score
						else
							retry = true
						end
 
						local slotID2 = EquipLocToSlot2[itemEquipLoc]
						if slotID2 then
							equippedLink = GetInventoryItemLink("player", slotID2)
							if equippedLink then
								local equippedScore2 =
									ScoreModule:CalculateItemScore(
										equippedLink,
										slotID2,
										ScanningTooltipModule:ScanTooltip(equippedLink),
										spec,
										equippedItemHasUniqueGem
									).Score
								if equippedScore or 0 > equippedScore2 then
									equippedScore = equippedScore2
								end
							else
								retry = true
							end
						end
 
						if equippedScore then
							if (score - equippedScore) / equippedScore * 100 > itemPercentUpgrade then
								itemPercentUpgrade = (score - equippedScore) / equippedScore * 100
							end
						end
					end
				end
				if itemPercentUpgrade >= self.db.profile.options.reward.gear.PercentUpgradeMin then
					local item = { itemLink = itemLink, itemPercentUpgrade = math.floor(itemPercentUpgrade + .5) }
					self:AddRewardToQuest(questID, "ITEM", item, isEmissary)
				end
			end
		end
 
		-- Upgrade by itemLevel
		if self.db.profile.options.reward.gear.itemLevelUpgrade then
			local itemLevel1, itemLevel2
			local slotID = EquipLocToSlot1[itemEquipLoc]
			if slotID then
				if GetInventoryItemID("player", slotID) then
					local itemLink1 = GetInventoryItemLink("player", slotID)
					if itemLink1 then
						itemLevel1 = GetDetailedItemLevelInfo(itemLink1)
						if not itemLevel1 then
							retry = true
						end
					else
						retry = true
					end
				end
			end
			if EquipLocToSlot2[itemEquipLoc] then
				slotID = EquipLocToSlot2[itemEquipLoc]
				if GetInventoryItemID("player", slotID) then
					local itemLink2 = GetInventoryItemLink("player", slotID)
					if itemLink2 then
						itemLevel2 = GetDetailedItemLevelInfo(itemLink2)
						if not itemLevel2 then
							retry = true
						end
					else
						retry = true
					end
				end
			end
 
			itemLevel = GetDetailedItemLevelInfo(itemLink)
			if not itemLevel then
				retry = true
			else
				local itemLevelEquipped = math.min(itemLevel1 or 1000, itemLevel2 or 1000)
				if itemLevel - itemLevelEquipped >= self.db.profile.options.reward.gear.itemLevelUpgradeMin then
					local item = { itemLink = itemLink, itemLevelUpgrade = itemLevel - itemLevelEquipped }
					self:AddRewardToQuest(questID, "ITEM", item, isEmissary)
				end
			end
		end
 
		-- Azerite Armor Cache
		if itemID == 163857 and self.db.profile.options.reward.gear.AzeriteArmorCache then
			itemLevel = GetDetailedItemLevelInfo(itemLink)
			local AzeriteArmorCacheIsUpgrade = false
			local AzeriteArmorCache = {}
			for i = 1, 5, 2 do
				if GetInventoryItemID("player", i) then
					local itemLink1 = GetInventoryItemLink("player", i)
					if itemLink1 then
						local itemLevel1 = GetDetailedItemLevelInfo(itemLink1)
						if itemLevel1 then
							AzeriteArmorCache[i] = itemLevel - itemLevel1
							if itemLevel > itemLevel1 and itemLevel - itemLevel1 >= self.db.profile.options.reward.gear.itemLevelUpgradeMin then
								AzeriteArmorCacheIsUpgrade = true
							end
						else
							retry = true
						end
					else
						retry = true
					end
				else
					AzeriteArmorCache[i] = itemLevel
					if itemLevel and itemLevel >= self.db.profile.options.reward.gear.itemLevelUpgradeMin then
						AzeriteArmorCacheIsUpgrade = true
					end
				end
			end
			if AzeriteArmorCacheIsUpgrade == true then
				local item = { itemLink = itemLink, AzeriteArmorCache = AzeriteArmorCache }
				self:AddRewardToQuest(questID, "ITEM", item, isEmissary)
			end
		end
 
		-- Equipment Cache
		if
			(weaponCache[itemID] and self.db.profile.options.reward.gear.weaponCache) or
			(armorCache[itemID] and self.db.profile.options.reward.gear.armorCache) or
			(jewelryCache[itemID] and self.db.profile.options.reward.gear.jewelryCache)
		then
			itemLevel = GetDetailedItemLevelInfo(itemLink)
			local n = 0
			local upgrade
			local upgradeMax = 0
			local upgradeSum = 0
			local upgradeNum = 0
 
			if weaponCache[itemID] then
				for i = 16, 17 do
					if GetInventoryItemID("player", i) then
						local itemLink1 = GetInventoryItemLink("player", i)
						if itemLink1 then
							local itemLevel1 = GetDetailedItemLevelInfo(itemLink1)
							if itemLevel1 then
								n = n + 1
								upgrade = itemLevel - itemLevel1
								if upgrade >= self.db.profile.options.reward.gear.itemLevelUpgradeMin then
									upgradeNum = upgradeNum + 1
									if upgrade > upgradeMax then
										upgradeMax = upgrade
									end
								end
								upgradeSum = upgradeSum + upgrade
							else
								retry = true
							end
						else
							retry = true
						end
					end
				end
			end
 
			if armorCache[itemID] then
				for i = 1, 10 do
					if i == 4 then
						i = 15
					end
					if i ~= 2 then
						if GetInventoryItemID("player", i) then
							local itemLink1 = GetInventoryItemLink("player", i)
							if itemLink1 then
								local itemLevel1 = GetDetailedItemLevelInfo(itemLink1)
								if itemLevel1 then
									n = n + 1
									upgrade = itemLevel - itemLevel1
									if upgrade >= self.db.profile.options.reward.gear.itemLevelUpgradeMin then
										upgradeNum = upgradeNum + 1
										if upgrade > upgradeMax then
											upgradeMax = upgrade
										end
									end
									upgradeSum = upgradeSum + upgrade
								else
									retry = true
								end
							else
								retry = true
							end
						end
					end
				end
			end
 
			if jewelryCache[itemID] then
				for i = 11, 14 do
					if GetInventoryItemID("player", i) then
						local itemLink1 = GetInventoryItemLink("player", i)
						if itemLink1 then
							local itemLevel1 = GetDetailedItemLevelInfo(itemLink1)
							if itemLevel1 then
								n = n + 1
								upgrade = itemLevel - itemLevel1
								if upgrade >= self.db.profile.options.reward.gear.itemLevelUpgradeMin then
									upgradeNum = upgradeNum + 1
									if upgrade > upgradeMax then
										upgradeMax = upgrade
									end
								end
								upgradeSum = upgradeSum + upgrade
							else
								retry = true
							end
						else
							retry = true
						end
					end
				end
			end
 
			if upgradeNum > 0 then
				local item = {
					itemLink = itemLink,
					cache = { upgradeNum = upgradeNum, n = n, upgradeMax = upgradeMax }
				}
				self:AddRewardToQuest(questID, "ITEM", item, isEmissary)
			end
		end
 
		-- Transmog
		if self.db.profile.options.reward.gear.unknownAppearance and self:IsTransmogable(itemLink) then
			if itemClassID == 2 or itemClassID == 4 then
				local transmog, transmogReason = self:EvaluateTransmogReward(itemLink)
				if transmog then
					if not isEmissary then
						self:TrackActiveTransmogReward(questID, itemLink, transmogReason)
					end
					local item = { itemLink = itemLink, transmog = transmog }
					self:AddRewardToQuest(questID, "ITEM", item, isEmissary)
				end
			end
		end

		-- Reputation Token
		local factionID = ReputationItemList[itemID] or nil
		if factionID then
			if self.db.profile.options.reward.reputation[factionID] == true then
				local reputation = { itemLink = itemLink, factionID = factionID }
				self:AddRewardToQuest(questID, "REPUTATION", reputation, isEmissary)
			end
		end
 
		-- Recipe
		if itemClassID == 9 then
			if self.db.profile.options.reward.recipe[expacID] == true then
				self:AddRewardToQuest(questID, "RECIPE", itemLink, isEmissary)
			end
		end
 
		-- Custom itemID
		if self.db.global.custom.worldQuestReward[itemID] == true then
			if self.db.profile.custom.worldQuestReward[itemID] == true then
				self:AddRewardToQuest(questID, "CUSTOM_ITEM", itemLink, isEmissary)
			end
		end
 
		-- Items
		if self.itemList[itemID] == true then
			local item = { itemLink = itemLink, _wqawOtherItemReason = true }
			self:AddRewardToQuest(questID, "ITEM", item, isEmissary)
		end
 
		-- Azerite Traits
		if
			self.db.profile.options.reward.gear.azeriteTraits ~= "" and
			C_AzeriteEmpoweredItem.IsAzeriteEmpoweredItemByID(itemLink)
		then
			for _, ring in pairs(C_AzeriteEmpoweredItem.GetAllTierInfoByItemID(itemLink)) do
				for _, azeritePowerID in pairs(ring.azeritePowerIDs) do
					local spellID = C_AzeriteEmpoweredItem.GetPowerInfo(azeritePowerID).spellID
					if self.azeriteTraitsList[spellID] then
						self:AddRewardToQuest(questID, "AZERITE_TRAIT", spellID, isEmissary)
						self:AddRewardToQuest(questID, "ITEM", { itemLink = itemLink, _wqawOtherItemReason = true }, isEmissary)
					end
				end
			end
		end
 
		-- Conduit
		if self.db.profile.options.reward.gear.conduit and C_Soulbinds.IsItemConduitByItemInfo(itemLink) then
			self:AddRewardToQuest(questID, "ITEM", { itemLink = itemLink, _wqawOtherItemReason = true }, isEmissary)
		end
	else
		retry = true
	end
 
	return retry
end
 
function WQA:CheckCurrencies(questID, isEmissary)
	local retry = false
	local questRewardCurrencies = C_QuestLog.GetQuestRewardCurrencies(questID) or {}

	self.rewardScanRawCurrencyRewardCounts = self.rewardScanRawCurrencyRewardCounts or {}
	self.rewardScanRawCurrencyRewardCounts[questID] = #questRewardCurrencies

	if #questRewardCurrencies == 0
		and self.backgroundScanInProgress
		and self:PreviousCommittedQuestHadCurrencyReward(questID)
	then
		self:Debug("Previously tracked currency reward unexpectedly returned empty", questID)
		self:QueueRewardPreload(questID, true)
		retry = true
	end

	for _, currencyInfo in ipairs(questRewardCurrencies) do
		local currencyID = currencyInfo.currencyID
		local amount = currencyInfo.totalRewardAmount

		if self.db.profile.options.reward.currency[currencyID] then
			local currency = { currencyID = currencyID, amount = amount }
			self:AddRewardToQuest(questID, "CURRENCY", currency, isEmissary)
		end

		local factionID = ReputationCurrencyList[currencyID] or nil
		if factionID and self.db.profile.options.reward.reputation[factionID] == true then
			local reputation = {
				name = currencyInfo.name,
				currencyID = currencyID,
				amount = amount,
				factionID = factionID
			}
			self:AddRewardToQuest(questID, "REPUTATION", reputation, isEmissary)
		end
	end

	local rawGoldMoney = GetQuestLogRewardMoney(questID) or 0
	self.rewardScanRawGoldRewardMoney = self.rewardScanRawGoldRewardMoney or {}
	self.rewardScanRawGoldRewardMoney[questID] = rawGoldMoney

	if rawGoldMoney == 0
		and self.backgroundScanInProgress
		and self:PreviousCommittedQuestHadGoldReward(questID)
	then
		self:Debug("Previously tracked gold reward unexpectedly returned zero", questID)
		self:QueueRewardPreload(questID, true)
		retry = true
	end

	local gold = math.floor(rawGoldMoney / 10000)
	if gold > 0 then
		if self.db.profile.options.reward.general.gold and gold >= self.db.profile.options.reward.general.goldMin then
			self:AddRewardToQuest(questID, "GOLD", gold, isEmissary)
		end
	end

	return retry
end
function WQA:Debug(...)
	if self.debug == true then
		print(GetTime(), GetFramerate(), ...)
	end
end
 
function WQA:RequestDisplayItemData(itemID)
	if type(itemID) ~= "number" or not C_Item or not C_Item.RequestLoadItemDataByID then
		return
	end

	self.pendingDisplayItemIDs = self.pendingDisplayItemIDs or {}
	self.displayItemLoadLastRequest = self.displayItemLoadLastRequest or {}

	if self.pendingDisplayItemIDs[itemID] then
		return
	end

	local now = GetTime and GetTime() or 0
	local lastRequest = self.displayItemLoadLastRequest[itemID]
	if lastRequest and now - lastRequest < 10 then
		return
	end

	self.pendingDisplayItemIDs[itemID] = true
	self.displayItemLoadLastRequest[itemID] = now
	self.event:RegisterEvent("ITEM_DATA_LOAD_RESULT")
	C_Item.RequestLoadItemDataByID(itemID)
end

function WQA:HandleDisplayItemDataResult(itemID, success)
	if not self.pendingDisplayItemIDs or not self.pendingDisplayItemIDs[itemID] then
		return
	end

	self.pendingDisplayItemIDs[itemID] = nil

	if success then
		self.displayItemLoadLastRequest[itemID] = nil
		-- Rebuilding the visible list will resolve and cache the real item link.
		self:RefreshVisibleTaskList()

		-- Never persist a background build. During normal display-only loading,
		-- save the newly resolved item link into the committed display cache.
		if not self.backgroundScanInProgress then
			self:SavePersistentDisplayCache()
		end
	end

	if not next(self.pendingDisplayItemIDs) then
		self.event:UnregisterEvent("ITEM_DATA_LOAD_RESULT")
	end
end

function WQA:GetRewardTextByID(questID, key, value, i, type)
	local k, v = key, value
	local text

	-- Multi-value reward types are stored as arrays.  Do not treat a
	-- nonexistent array slot as an uncached reward: callers deliberately
	-- probe slots 2-4 to decide whether to append more rewards.
	if (k == "achievement" or k == "chance" or k == "azeriteTraits") and not v[i] then
		return nil
	end

	if k == "custom" then
		text = "Custom"
	elseif k == "item" then
		text = self:GetRewardForID(questID, k, type)
	elseif k == "reputation" then
		if v.itemLink then
			text = self:GetRewardLinkByID(questID, k, v, i)
		else
			text = v.amount .. " " .. self:GetRewardLinkByID(questID, k, v, i)
		end
	elseif k == "currency" then
		text = v.amount .. " " .. GetCurrencyLink(v.currencyID, v.amount)
	elseif k == "professionSkillup" then
		text = v
	elseif k == "gold" then
		text = GOLD_AMOUNT_TEXTURE_STRING:format(v, 0, 0)
	else
		text = self:GetRewardLinkByID(questID, k, v, i)
		-- Some legacy rewards are not immediately cached by Retail 12.1.0.
		-- Never let a missing link prevent the world quest itself from being shown.
		if not text then
			if k == "chance" and v[i] and v[i].id then
				self:RequestDisplayItemData(v[i].id)
				text = v[i].displayName or ("Item " .. tostring(v[i].id))
			elseif k == "achievement" and v[i] and v[i].id then
				text = "Achievement " .. tostring(v[i].id)
			elseif k == "azeriteTraits" and v[i] and v[i].spellID then
				text = "Spell " .. tostring(v[i].spellID)
			else
				text = "Reward unavailable"
			end
		end
	end
	return text
end
 
function WQA:GetRewardLinkByMissionID(missionID, key, value, i)
	return self:GetRewardLinkByID(missionID, key, value, i)
end
 
function WQA:GetRewardLinkByID(questID, key, value, i)
	local k, v = key, value
	local link = nil
	if k == "achievement" then
		if not v[i] then
			return nil
		end
		link = v[i].achievementLink or GetAchievementLink(v[i].id)
	elseif k == "chance" then
		if not v[i] then
			return nil
		end
		link = v[i].itemLink or select(2, GetItemInfo(v[i].id))
		if link then
			v[i].itemLink = link
		else
			self:RequestDisplayItemData(v[i].id)
		end
	elseif k == "custom" then
		return nil
	elseif k == "item" then
		link = v.itemLink
	elseif k == "reputation" then
		if v.itemLink then
			link = v.itemLink
		else
			link = v.currencyLink or GetCurrencyLink(v.currencyID, v.amount)
		end
	elseif k == "recipe" then
		link = v
	elseif k == "customItem" then
		link = v
	elseif k == "currency" then
		link = v.currencyLink or GetCurrencyLink(v.currencyID, v.amount)
	elseif k == "professionSkillup" then
		return nil
	elseif k == "gold" then
		return nil
	elseif k == "azeriteTraits" then
		if not v[i] then
			return nil
		end
		link = GetSpellLink(v[i].spellID)
	elseif k == WQA.Rewards.RewardType.Miscellaneous then
		link = table.concat(v, ", ")
	end
	return link
end
 
function WQA:SetRewardLinkByMissionID(missionID, key, value, i, link)
	self:SetRewardLinkByID(missionID, key, value, i, link)
end
 
function WQA:SetRewardLinkByID(questID, key, value, i, link)
	local k, v = key, value
	if k == "achievement" then
		v[i].achievementLink = link
	elseif k == "chance" then
		v[i].itemLink = link
	elseif k == "reputation" then
		if not v.itemLink then
			v.currencyLink = link
		end
	elseif k == "currency" then
		v.currencyLink = link
	end
end
 
local function GetQuestName(questID)
	return C_TaskQuest.GetQuestInfoByQuestID(questID) or GetTitleForQuestID(questID) or
		select(3, string.find(GetQuestLink(questID) or "[unknown]", "%[(.+)%]"))
end
 
local function GetMissionName(missionID)
	return C_Garrison.GetMissionName(missionID)
end
 
local function GetTaskSortName(task)
	if task.type == "WORLD_QUEST" then
		return GetQuestName(task.id) or ""
	elseif task.type == "AREA_POI" then
		local poiInfo = C_AreaPoiInfo.GetAreaPOIInfo(task.mapId, task.id)
		if poiInfo and poiInfo.name then
			return poiInfo.name
		end
		local schedulerInfo = WQA:GetScheduledAreaPoiInfo(task.id, task.mapId)
		if schedulerInfo and schedulerInfo.name then
			return schedulerInfo.name
		end
		local scenarioInfo = WQA:GetScenarioAreaPoiInfo(task.id, task.mapId)
		if scenarioInfo and scenarioInfo.name then
			return scenarioInfo.name
		end
		local entry = WQA.Criterias.AreaPoi.list[task.id] and WQA.Criterias.AreaPoi.list[task.id][task.mapId]
		return (entry and entry.name) or ""
	else
		return GetMissionName(task.id) or ""
	end
end

local function SortByName(a, b)
	return GetTaskSortName(a) < GetTaskSortName(b)
end
 
function WQA:InsertionSort(A, compareFunction)
	for i, v in ipairs(A) do
		local j = i
		while j > 1 and compareFunction(A[j], A[j - 1]) do
			local temp = A[j]
			A[j] = A[j - 1]
			A[j - 1] = temp
			j = j - 1
		end
	end
	return A
end
 
function WQA:SortQuestList(list)
	if self.db.profile.options.sortByName == true then
		list = self:InsertionSort(list, SortByName)
	end
 
	if self.db.profile.options.sortByZoneName == true then
		list = self:InsertionSort(list, function(a, b) return self:SortByZoneName(a, b) end)
	end
 
	list = self:InsertionSort(list, function(a, b) return self:SortByExpansion(a, b) end)
	return list
end
 
local GetBountiesForMapIDRequested = false
function WQA:EmissaryReward()
	self.emissaryRewards = false
	local retry = false
 
	for _, mapID in pairs({ 627, 875 }) do
		local bounties = GetBountiesForMapID(mapID)
		if bounties then
			for _, emissary in ipairs(GetBountiesForMapID(mapID)) do
				local questID = emissary.questID
				if self.db.profile.options.emissary[questID] == true then
					self:AddEmissaryReward(questID, "CUSTOM", nil, true)
				end
				-- Targeted emissary retries
				if HaveQuestData(questID) and HaveQuestRewardData(questID) then
					if self:CheckItems(questID, true) then
						retry = true
						self.pendingQuests[questID] = true
					end
					if self:CheckCurrencies(questID, true) then
						retry = true
						self.pendingQuests[questID] = true
					end
				else
					retry = true
					self.pendingQuests[questID] = true
					self:QueueRewardPreload(questID)
				end
			end
		end
	end
 
	if retry == true then
		GetBountiesForMapIDRequested = true
		self.event:RegisterEvent("QUEST_LOG_UPDATE")
		self.event:RegisterEvent("GET_ITEM_INFO_RECEIVED")
		self:StartRewardPreloadQueue()
		self:SchedulePendingRewardCheck(1)
	else
		GetBountiesForMapIDRequested = false
		self.emissaryRewards = true

		if not self.rewardDiscoveryFinalizing then
			local callbackMode = self.pendingRefreshMode or self.backgroundScanMode or self.rewardContinuationMode or self.lastMode
			if callbackMode then
				self:CheckWQ(callbackMode)
			end
		end
	end
end
 
function WQA:EmissaryIsActive(questID)
	local emissary = {}
	for _, v in pairs(self.EmissaryQuestIDList) do
		for _, id in pairs(v) do
			if type(id) == "table" then
				id = id.id
			end
			if id == questID then
				emissary[id] = true
			end
		end
	end
 
	if emissary[questID] ~= true then
		return false
	end
 
	local i = 1
	while C_QuestLog.GetInfo(i) do
		local questLogQuestID = C_QuestLog.GetInfo(i).questID
		if questLogQuestID == questID then
			return true
		end
		i = i + 1
	end
	return false
end
 
function WQA:Special()
	if
		(self.db.profile.achievements[11189] ~= "disabled" and not select(4, GetAchievementInfo(11189)) == true) or
		(self.db.profile.achievements[13144] ~= "disabled" and not select(4, GetAchievementInfo(13144)) == true) or
		(self.db.profile.achievements[14758] ~= "disabled" and not select(4, GetAchievementInfo(14758)))
	then
		self.event:RegisterEvent("QUEST_TURNED_IN")
	end
end
 
local function PopUpIsShown()
	if WQA.PopUp then
		return WQA.PopUp.shown
	else
		return false
	end
end
 
local anchor
function dataobj:OnEnter()
	anchor = self
	WQA:PruneExpiredCachedWorldQuests(false)
	if not PopUpIsShown() then
		-- Silent transmog refreshes are double-buffered: while the new scan is
		-- resolving reward data, the last committed quest state remains live.
		-- Hover therefore stays responsive and renders a fully consistent cached
		-- list until the completed refresh is swapped in atomically.
		-- Do not run a full WQA:Show()/CreateQuestList() scan from a mouse-hover
		-- handler. Retail executes this synchronously on the UI thread and the old
		-- behavior can freeze the client until all quest/reward data is rebuilt.
		-- The normal login/periodic scans keep activeTasks up to date, so the
		-- minimap tooltip should only render that cached result.
		WQA:WithCommittedScanState(function()
			WQA:AnnounceLDB(WQA.activeTasks or {})
		end)
	end
end
 
function dataobj:OnClick(button)
	if button == "LeftButton" then
		if IsShiftKeyDown() then
			WQA:RequestFullRefresh("minimap Shift+Left Click", false)
		else
			WQA:Show("popup")
		end
	elseif button == "RightButton" then
		WQA:EnsureOptionsRegistered()
		Settings.OpenToCategory(WQA.optionsCategoryID or (WQA.optionsFrame and WQA.optionsFrame.name))
	end
end
 
function WQA:AnnounceLDB(quests)
	-- Hide PopUp
	if PopUpIsShown() then
		return
	end
 
	self:CreateQTip()
	self.tooltip.showMinimapRefreshHint = true
	self.tooltip:SetAutoHideDelay(
		.25,
		anchor,
		function()
			if not PopUpIsShown() then
				LibQTip:Release(WQA.tooltip)
				WQA.tooltip.quests = nil
				WQA.tooltip.missions = nil
				WQA.tooltip.pois = nil
				WQA.tooltip = nil
			end
		end
	)
	self.tooltip:SmartAnchorTo(anchor)
	self:UpdateQTip(quests)
end
 
function WQA:UpdateLDBText(activeTasks, newTasks)
	if newTasks ~= nil then
		dataobj.text = "New World Quests active"
	elseif activeTasks ~= nil then
		dataobj.text = "World Quests active"
	else
		dataobj.text = "No World Quests active"
	end
end
 
function WQA:formatTime(t)
	local t = math.floor(t or 0)
	local d, h, m, timeString
	d = math.floor(t / 60 / 24)
	h = math.floor(t / 60 % 24)
	m = t % 60
	if d > 0 then
		if h > 0 then
			timeString = string.format("%dd %dh", d, h)
		else
			timeString = string.format("%dd", d)
		end
	elseif h > 0 then
		if m > 0 then
			timeString = string.format("%dh %dm", h, m)
		else
			timeString = string.format("%dh", h)
		end
	else
		timeString = string.format("%dm", m)
	end
 
	if t > 0 then
		if t <= 180 then
			if t <= 30 then
				timeString = string.format("|cffff3333%s|r", timeString)
			else
				timeString = string.format("|cffffff00%s|r", timeString)
			end
		end
	end
 
	return timeString
end
 
local LE_GARRISON_TYPE = {
	[6] = Enum.GarrisonType.Type_6_0_Garrison,
	[7] = Enum.GarrisonType.Type_7_0_Garrison,
	[8] = Enum.GarrisonType.Type_8_0_Garrison,
	[9] = Enum.GarrisonType.Type_9_0_Garrison
}
 
function WQA:CheckMissions()
	local activeMissions = {}
	local retry
	for i in pairs(WQA.ExpansionList) do
		local type = LE_GARRISON_TYPE[i]
		local followerType = GetPrimaryGarrisonFollowerType(type)
		if type and C_Garrison.HasGarrison(type) then
			local missions = C_Garrison.GetAvailableMissions(followerType)
			-- Add Shipyard Missions
			if i == 6 and C_Garrison.HasShipyard() then
				for missionID, mission in ipairs(C_Garrison.GetAvailableMissions(Enum.GarrisonFollowerType.FollowerType_6_0_Boat)) do
					mission.followerType = Enum.GarrisonFollowerType.FollowerType_6_0_Boat
					missions[#missions + 1] = mission
				end
			end
 
			if missions then
				for _, mission in ipairs(missions) do
					local missionID = mission.missionID
					local addMission = false
					if self.missionList[missionID] then
						addMission = true
					end
					for _, reward in ipairs(mission.rewards) do
						if reward.currencyID then
							if reward.currencyID ~= 0 then
								local currencyID = reward.currencyID
								local amount = reward.quantity
								if self.db.profile.options.missionTable.reward.currency[currencyID] then
									local currency = { currencyID = currencyID, amount = amount }
									self:AddRewardToMission(missionID, "CURRENCY", currency)
									addMission = true
								else
									local factionID = ReputationCurrencyList[currencyID] or nil
									if factionID then
										if self.db.profile.options.missionTable.reward.reputation[factionID] == true then
											local reputation = {
												currencyID = currencyID,
												amount = amount,
												factionID = factionID
											}
											self:AddRewardToMission(missionID, "REPUTATION", reputation)
										end
									end
								end
							else
								local gold = math.floor(reward.quantity / 10000)
								if
									self.db.profile.options.missionTable.reward.gold and
									gold >= self.db.profile.options.missionTable.reward.goldMin
								then
									self:AddRewardToMission(missionID, "GOLD", gold)
									addMission = true
								end
							end
						end
 
						if reward.itemID then
							local itemID = reward.itemID
							local itemName,
							itemLink,
							itemRarity,
							itemLevel,
							itemMinLevel,
							itemType,
							itemSubType,
							itemStackCount,
							itemEquipLoc,
							itemTexture,
							itemSellPrice,
							itemClassID,
							itemSubClassID = GetItemInfo(itemID)
 
							if not itemLink then
								retry = true
							else
								-- Custom Mission Reward
								if self.db.global.custom.missionReward[itemID] and self.db.profile.custom.missionReward[itemID] then
									local item = { itemLink = itemLink }
									self:AddRewardToMission(missionID, "ITEM", item)
									addMission = true
								end
 
								-- Reputation Token
								local factionID = ReputationItemList[itemID] or nil
								if factionID then
									if self.db.profile.options.missionTable.reward.reputation[factionID] == true then
										local reputation = { itemLink = itemLink, factionID = factionID }
										self:AddRewardToMission(missionID, "REPUTATION", reputation)
										addMission = true
									end
								end
 
								-- Transmog
								if self.db.profile.options.reward.gear.unknownAppearance and self:IsTransmogable(itemLink) then
									if itemClassID == 2 or itemClassID == 4 then
										local transmog
										local searchForLinkResult = SearchAllTheThingsSafely(itemLink)
										if searchForLinkResult and searchForLinkResult[1] then
											local state = searchForLinkResult[1].collected
											if not state then
												transmog = "|TInterface\\Addons\\AllTheThings\\assets\\unknown:0|t"
											elseif state == 2 and self.db.profile.options.reward.gear.unknownSource then
												transmog = "|TInterface\\Addons\\AllTheThings\\assets\\known_circle:0|t"
											end
										end

										if CanIMogIt and not transmog then
											if CanIMogIt:IsEquippable(itemLink) and CanIMogIt:CharacterCanLearnTransmog(itemLink) then
												if not CanIMogIt:PlayerKnowsTransmog(itemLink) then
													transmog = "|TInterface\\AddOns\\CanIMogIt\\Icons\\UNKNOWN:0|t"
												elseif not CanIMogIt:PlayerKnowsTransmogFromItem(itemLink) and self.db.profile.options.reward.gear.unknownSource then
													transmog = "|TInterface\\AddOns\\CanIMogIt\\Icons\\KNOWN_circle:0|t"
												end
											end
										end
										if transmog then
											local item = { itemLink = itemLink, transmog = transmog }
											self:AddRewardToMission(missionID, "ITEM", item)
											addMission = true
										end
									end
								end
 
								-- Conduit
								if self.db.profile.options.reward.gear.conduit and C_Soulbinds.IsItemConduitByItemInfo(itemLink) then
									self:AddRewardToMission(missionID, "ITEM", { itemLink = itemLink })
									addMission = true
								end
							end
						end
						if addMission == true then
							self.missionList[missionID].offerEndTime = mission.offerEndTime or nil
							self.missionList[missionID].offerTimeRemaining = mission.offerTimeRemaining or nil
							self.missionList[missionID].expansion = i
							self.missionList[missionID].followerType = mission.followerType or followerType
							activeMissions[missionID] = true
						end
					end
				end
			end
		end
	end
 
	if retry then
		return nil
	else
		return activeMissions
	end
end
 
function WQA:isQuestPinActive(questID)
	for mapID in pairs(self.questPinMapList) do
		for _, questPin in pairs(C_QuestLine.GetAvailableQuestLines(mapID)) do
			if questPin.questID == questID then
				return true
			end
		end
	end
	return false
end
 
function WQA:IsQuestFlaggedCompleted(questID)
	if self.questFlagList[questID] then
		return not IsQuestFlaggedCompleted(questID)
	else
		return false
	end
end
 
function WQA:UpdateMinimapIcon()
	if self.db.profile.options.LibDBIcon.hide then
		icon:Hide("WorldQuestAchievementWatcher")
	else
		icon:Show("WorldQuestAchievementWatcher")
	end
end