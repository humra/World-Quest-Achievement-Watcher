---@class WorldQuestAchievementWatcher : AceAddon
---@field tooltip LibQTip.Tooltip
WorldQuestAchievementWatcher = LibStub("AceAddon-3.0"):NewAddon("WorldQuestAchievementWatcher", "AceConsole-3.0", "AceTimer-3.0")

---@class WorldQuestAchievementWatcher
local WQA = WorldQuestAchievementWatcher

WQA.data = {}
WQA.watched = {}
WQA.watchedMissions = {}
WQA.questList = {}
WQA.missionList = {}
WQA.itemList = {}
WQA.links = {}
WQA.Criterias = {}
WQA.Rewards = {}
