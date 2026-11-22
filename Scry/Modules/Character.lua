-- Module "character": who this character is. Also the reference example of a data
-- module: own one section of ScryDB, write on events, Touch() after writing,
-- register a selftest for the live-API assumptions.
local _, ns = ...

local Character = ns:NewModule("character")

local function record(level)
	local section = ns.DB:Section("character")
	local _, classToken = UnitClass("player")
	local _, raceToken = UnitRace("player")
	section.name = UnitName("player")
	section.realm = GetRealmName()
	section.class = classToken
	section.race = raceToken
	section.faction = UnitFactionGroup("player")
	section.level = level or UnitLevel("player")
	section.guid = UnitGUID("player")
	ns.DB:Touch(section)
end

function Character:OnLogin()
	record()
end

ns:On("PLAYER_LEVEL_UP", function(newLevel)
	record(newLevel)
end)

ns.SelfTest:Register("character: section is populated from the live client", function()
	local s = ns.DB:Section("character")
	assert(type(s.name) == "string" and s.name ~= "", "name")
	assert(type(s.realm) == "string" and s.realm ~= "", "realm")
	assert(type(s.class) == "string" and s.class == s.class:upper(), "class token: " .. tostring(s.class))
	assert(type(s.race) == "string", "race token")
	assert(
		s.faction == "Alliance" or s.faction == "Horde" or s.faction == "Neutral",
		"faction: " .. tostring(s.faction)
	)
	assert(type(s.level) == "number" and s.level >= 1, "level")
	assert(type(s.guid) == "string" and s.guid:match("^Player%-"), "guid: " .. tostring(s.guid))
end)
