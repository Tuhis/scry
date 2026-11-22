-- Module "talents": active specialization and class talent choices.
local _, ns = ...

local Talents = ns:NewModule("talents")

local function record()
	local section = ns.DB:Section("talents")
	local specIndex = C_SpecializationInfo.GetSpecialization()
	local specID, specName
	if specIndex and specIndex > 0 then
		specID, specName = C_SpecializationInfo.GetSpecializationInfo(specIndex)
	end
	section.specID = specID and specID > 0 and specID or nil
	ns.DB:Name("specs", section.specID, specName)

	local nodes = {}
	local configID = C_ClassTalents.GetActiveConfigID()
	local config = configID and C_Traits.GetConfigInfo(configID)
	if configID and config then
		for _, treeID in ipairs(config.treeIDs or {}) do
			for nodeID, rank in pairs(ns.TraitNodes(configID, treeID)) do
				nodes[nodeID] = rank
			end
		end
		local loadout = C_Traits.GenerateImportString(configID)
		section.loadout = loadout and loadout ~= "" and loadout or nil
	end
	section.nodes = nodes
	ns.DB:Touch(section)
	ns.Log:Debug(("talents: spec %s, config %s"):format(tostring(specID), tostring(configID)))
end

function Talents:OnLogin()
	record()
end

for _, event in ipairs({ "TRAIT_CONFIG_UPDATED", "PLAYER_TALENT_UPDATE", "PLAYER_SPECIALIZATION_CHANGED" }) do
	ns:On(event, function()
		ns:Debounce("talents.record", 1, record)
	end)
end

ns.SelfTest:Register("talents: the talent tree is readable", function()
	if UnitLevel("player") < 15 then
		return -- may have no talent points yet
	end
	assert(C_ClassTalents.GetActiveConfigID(), "no active class talent config")
	assert(next(ns.DB:Section("talents").nodes) ~= nil, "no talent nodes with ranks")
end)
