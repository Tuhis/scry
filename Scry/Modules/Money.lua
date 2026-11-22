-- Module "money": gold carried by the character, in copper.
local _, ns = ...

local Money = ns:NewModule("money")

local function record()
	local section = ns.DB:Section("money")
	section.copper = GetMoney()
	ns.DB:Touch(section)
end

function Money:OnLogin()
	record()
end

ns:On("PLAYER_MONEY", record)

ns.SelfTest:Register("money: copper is a non-negative number", function()
	local s = ns.DB:Section("money")
	assert(type(s.copper) == "number" and s.copper >= 0, "copper: " .. tostring(s.copper))
end)
