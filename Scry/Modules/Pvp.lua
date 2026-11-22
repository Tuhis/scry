-- Module "pvp": lifetime PvP record.
local _, ns = ...

local Pvp = ns:NewModule("pvp")

local function record()
	local section = ns.DB:Section("pvp")
	local honorableKills, highestRank = GetPVPLifetimeStats()
	section.honorableKills = honorableKills or 0
	section.highestRank = highestRank or 0 -- Enum.PvPRanks
	ns.DB:Touch(section)
end

function Pvp:OnLogin()
	record()
end

ns:On("PLAYER_PVP_KILLS_CHANGED", record)
