-- Module "character": who this character is. Also the reference example of a data
-- module: own one section of ScryDB, write on events, Touch() after writing,
-- register a selftest for the live-API assumptions.
local _, ns = ...

local Character = ns:NewModule("character")

local SEX = { [Enum.UnitSex.Male] = "male", [Enum.UnitSex.Female] = "female" }
local PRESET = {
	[Enum.ForeverExperiencePreset.Classic] = "classic",
	[Enum.ForeverExperiencePreset.Enhanced] = "enhanced",
}

local function record(level)
	local section = ns.DB:Section("character")
	local _, classToken = UnitClass("player")
	local _, raceToken = UnitRace("player")
	section.name = UnitName("player")
	section.class = classToken
	section.race = raceToken
	section.faction = UnitFactionGroup("player")
	section.level = level or UnitLevel("player")
	section.guid = UnitGUID("player")

	section.xp = UnitXP("player")
	section.xpMax = UnitXPMax("player")
	section.restedXp = GetXPExhaustion() or 0
	section.zone = C_Map.GetBestMapForUnit("player") -- nil where the map is unknown
	local map = section.zone and C_Map.GetMapInfo(section.zone)
	ns.DB:Name("maps", section.zone, map and map.name)
	section.bindLocation = GetBindLocation()
	local guildName, guildRankName, guildRankIndex = GetGuildInfo("player")
	section.guild = guildName and { name = guildName, rank = guildRankName, rankIndex = guildRankIndex } or nil
	section.hardcore = C_GameRules.IsHardcoreActive() and true or false
	local preset = C_GameRules.GetForeverExperiencePreset()
	section.experiencePreset = preset and PRESET[preset] or nil
	ns.DB:Touch(section)
end

function Character:OnLogin()
	record()
	-- Read once at login: UnitSexBase can return a secret value in restricted situations.
	local sex = UnitSexBase("player")
	ns.DB:Section("character").sex = sex and SEX[sex] or "other"
end

ns:On("PLAYER_LEVEL_UP", function(newLevel)
	record(newLevel)
end)
for _, event in ipairs({ "PLAYER_XP_UPDATE", "ZONE_CHANGED_NEW_AREA", "PLAYER_GUILD_UPDATE", "PLAYER_LOGOUT" }) do
	ns:On(event, function()
		record()
	end)
end

ns.SelfTest:Register("character: section is populated from the live client", function()
	local s = ns.DB:Section("character")
	assert(type(s.name) == "string" and s.name ~= "", "name")
	assert(type(s.class) == "string" and s.class == s.class:upper(), "class token: " .. tostring(s.class))
	assert(type(s.race) == "string", "race token")
	assert(
		s.faction == "Alliance" or s.faction == "Horde" or s.faction == "Neutral",
		"faction: " .. tostring(s.faction)
	)
	assert(type(s.level) == "number" and s.level >= 1, "level")
	assert(type(s.guid) == "string" and s.guid:match("^Player%-"), "guid: " .. tostring(s.guid))
	assert(s.sex == "male" or s.sex == "female", "sex: " .. tostring(s.sex))
	assert(type(s.xp) == "number" and type(s.xpMax) == "number", "xp")
	assert(type(s.bindLocation) == "string", "bindLocation: " .. tostring(s.bindLocation))
	assert(type(s.zone) == "number", "zone: " .. tostring(s.zone))
end)
