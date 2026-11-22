-- Module "quests": IDs of every quest the character has completed.
local _, ns = ...

local Quests = ns:NewModule("quests")

local function record()
	local section = ns.DB:Section("quests")
	local completed = C_QuestLog.GetAllCompletedQuestIDs() or {}
	table.sort(completed)
	section.completed = completed
	ns.DB:Touch(section)
end

function Quests:OnLogin()
	record()
end

ns:On("QUEST_TURNED_IN", function()
	ns:Debounce("quests.record", 2, record)
end)
