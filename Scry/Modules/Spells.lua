-- Module "spells": spells in the spellbook, player and pet, keyed by spell ID.
local _, ns = ...

local Spells = ns:NewModule("spells")

-- The rank is only available as the localized text under the spell name
-- ("Rank 3"); the number in it is the same in every language.
local function entry(info)
	local subtext = info.subName
	if not subtext or subtext == "" then
		subtext = C_Spell.GetSpellSubtext(info.spellID)
	end
	return {
		passive = info.isPassive and true or false,
		rank = subtext and tonumber(subtext:match("%d+")) or nil,
	}
end

local function readSlot(out, slot, bank)
	local info = C_SpellBook.GetSpellBookItemInfo(slot, bank)
	if info and info.spellID and info.itemType == Enum.SpellBookItemType.Spell and not info.isOffSpec then
		out[info.spellID] = entry(info)
		return info
	end
end

local function record()
	local section = ns.DB:Section("spells")
	local player, sample = {}, {}
	for lineIndex = 1, C_SpellBook.GetNumSpellBookSkillLines() do
		local line = C_SpellBook.GetSpellBookSkillLineInfo(lineIndex)
		if line then
			for slot = line.itemIndexOffset + 1, line.itemIndexOffset + line.numSpellBookItems do
				local info = readSlot(player, slot, Enum.SpellBookSpellBank.Player)
				if info and #sample < 5 then
					sample[#sample + 1] = ("%d %s [%s]"):format(
						info.spellID,
						tostring(info.name),
						tostring(info.subName)
					)
				end
			end
		end
	end
	section.player = player

	-- Keep the last known pet spells while no pet is out.
	local numPetSpells = C_SpellBook.HasPetSpells()
	if numPetSpells and numPetSpells > 0 then
		local pet = {}
		for slot = 1, numPetSpells do
			readSlot(pet, slot, Enum.SpellBookSpellBank.Pet)
		end
		section.pet = pet
	end
	ns.DB:Touch(section)
	ns.Log:Debug("spells: " .. table.concat(sample, "; "))
end

function Spells:OnLogin()
	record()
end

ns:On("SPELLS_CHANGED", function()
	ns:Debounce("spells.record", 1, record)
end)

ns.SelfTest:Register("spells: the spellbook lists spells", function()
	local s = ns.DB:Section("spells")
	assert(next(s.player) ~= nil, "no player spells found")
end)
