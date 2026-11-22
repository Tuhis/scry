-- Module "reputations": standing with every faction the character has met.
local _, ns = ...

local Reputations = ns:NewModule("reputations")

local function record()
	local section = ns.DB:Section("reputations")
	local factions = {}
	for index = 1, C_Reputation.GetNumFactions() do
		local data = C_Reputation.GetFactionDataByIndex(index)
		if data and data.factionID and data.factionID > 0 and (not data.isHeader or data.isHeaderWithRep) then
			factions[data.factionID] = { standing = data.reaction, value = data.currentStanding }
			ns.DB:Name("factions", data.factionID, data.name)
		end
	end
	section.factions = factions
	ns.DB:Touch(section)
end

function Reputations:OnLogin()
	record()
end

ns:On("UPDATE_FACTION", function()
	ns:Debounce("reputations.record", 2, record)
end)

ns.SelfTest:Register("reputations: at least one faction is listed", function()
	assert(next(ns.DB:Section("reputations").factions) ~= nil, "no factions (collapsed headers hide them?)")
end)
