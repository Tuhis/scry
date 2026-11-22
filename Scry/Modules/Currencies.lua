-- Module "currencies": amounts of every currency in the currency list.
local _, ns = ...

local Currencies = ns:NewModule("currencies")

local function record()
	local section = ns.DB:Section("currencies")
	local amounts = {}
	for index = 1, C_CurrencyInfo.GetCurrencyListSize() do
		local info = C_CurrencyInfo.GetCurrencyListInfo(index)
		if info and not info.isHeader and info.currencyID and info.currencyID > 0 then
			amounts[info.currencyID] = info.quantity
			ns.DB:Name("currencies", info.currencyID, info.name)
		end
	end
	section.amounts = amounts
	ns.DB:Touch(section)
end

function Currencies:OnLogin()
	record()
end

ns:On("CURRENCY_DISPLAY_UPDATE", function()
	ns:Debounce("currencies.record", 2, record)
end)
