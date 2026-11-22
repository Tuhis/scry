-- Module "bags": items carried (backpack, bags, reagent bag) as itemID -> count.
local _, ns = ...

local Bags = ns:NewModule("bags")

local BAGS = {}
for bagID = Enum.BagIndex.Backpack, Enum.BagIndex.ReagentBag do
	BAGS[#BAGS + 1] = bagID
end

local function record()
	ns.Items:Record(ns.DB:Section("bags"), BAGS)
end

function Bags:OnLogin()
	record()
end

ns:On("BAG_UPDATE_DELAYED", record)

ns.SelfTest:Register("bags: the backpack is visible", function()
	local s = ns.DB:Section("bags")
	assert(s.slots.total >= 16, "total slots: " .. tostring(s.slots.total))
	assert(s.slots.free >= 0 and s.slots.free <= s.slots.total, "free slots: " .. tostring(s.slots.free))
	assert(type(s.vendorValue) == "number" and s.vendorValue >= 0, "vendorValue")
	assert(next(s.items) ~= nil, "no items seen in any bag")
end)
