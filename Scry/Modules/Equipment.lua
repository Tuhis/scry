-- Module "equipment": what is equipped, per inventory slot, with the full item
-- link (the link carries enchants and random suffixes).
local _, ns = ...

local Equipment = ns:NewModule("equipment")

local FIRST_SLOT, LAST_SLOT = 1, 19 -- INVSLOT_HEAD .. INVSLOT_TABARD

local function record()
	local section = ns.DB:Section("equipment")
	local slots = {}
	for slot = FIRST_SLOT, LAST_SLOT do
		local itemID = GetInventoryItemID("player", slot)
		if itemID then
			slots[slot] = { itemID = itemID, link = GetInventoryItemLink("player", slot) }
		end
	end
	section.slots = slots
	ns.DB:Touch(section)
end

function Equipment:OnLogin()
	record()
end

ns:On("PLAYER_EQUIPMENT_CHANGED", function()
	ns:Debounce("equipment.record", 0.5, record)
end)

ns.SelfTest:Register("equipment: equipped items have links", function()
	local s = ns.DB:Section("equipment")
	assert(next(s.slots) ~= nil, "nothing equipped?")
	for slot, item in pairs(s.slots) do
		assert(
			type(item.link) == "string" and item.link:find("item:", 1, true),
			"slot " .. slot .. " link: " .. tostring(item.link)
		)
	end
end)
