-- Module "bank": items in the character's bank tabs, as itemID -> count. The bank
-- is only readable while its window is open, so this is a snapshot of the last visit.
local _, ns = ...

ns:NewModule("bank")

local isOpen = false

local function record()
	if not isOpen then
		return
	end
	local tabIDs = C_Bank.FetchPurchasedBankTabIDs(Enum.BankType.Character) or {}
	ns.Items:Record(ns.DB:Section("bank"), tabIDs)
	ns.Log:Debug(("bank: scanned %d tab(s)"):format(#tabIDs))
end

ns:On("BANKFRAME_OPENED", function()
	isOpen = true
	record()
end)
ns:On("BANKFRAME_CLOSED", function()
	isOpen = false
end)
ns:On("BAG_UPDATE_DELAYED", record)
ns:On("PLAYERBANKSLOTS_CHANGED", record)

ns.SelfTest:Register("bank: snapshot is consistent (after a bank visit)", function()
	local s = ns.DB:Peek("bank")
	if not s then
		return -- bank not visited yet with the addon
	end
	assert(s.slots.total > 0, "bank scanned but no slots seen: tab IDs are probably wrong")
	assert(s.slots.free <= s.slots.total, "free slots")
end)
