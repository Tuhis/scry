-- Module "quests": IDs of every quest the character has completed.
local _, ns = ...

local Quests = ns:NewModule("quests")

-- Quests whose title the client had to fetch from the server first.
local untitled = {}

local function name(questID)
	local title = C_QuestLog.GetTitleForQuestID(questID)
	if title and title ~= "" then
		ns.DB:Name("quests", questID, title)
		untitled[questID] = nil
	elseif not untitled[questID] then
		untitled[questID] = true
		C_QuestLog.RequestLoadQuestByID(questID)
	end
end

local function record()
	local section = ns.DB:Section("quests")
	local completed = C_QuestLog.GetAllCompletedQuestIDs() or {}
	table.sort(completed)
	section.completed = completed
	ns.DB:Touch(section)
	local names = ns.DB.db.names.quests
	for _, questID in ipairs(completed) do
		if not names[questID] then
			name(questID)
		end
	end
end

ns:On("QUEST_DATA_LOAD_RESULT", function(questID, success)
	if success and untitled[questID] then
		name(questID)
	end
end)

function Quests:OnLogin()
	record()
end

ns:On("QUEST_TURNED_IN", function()
	ns:Debounce("quests.record", 2, record)
end)
