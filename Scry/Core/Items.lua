-- Shared item scanning for the "bags" and "bank" modules: containers -> itemID
-- counts, slot usage and vendor value.
local _, ns = ...

local Items = {}
ns.Items = Items

-- Sections whose vendorValue is incomplete because item data was not cached yet.
local unpriced = {}

--- Vendor value in copper of an itemID -> count map. Second result: number of
--- items whose price is not known yet (their data is requested from the server).
function Items:VendorValue(items)
	local value, missing = 0, 0
	for itemID, count in pairs(items) do
		local sellPrice = select(11, C_Item.GetItemInfo(itemID))
		if sellPrice then
			value = value + sellPrice * count
		else
			missing = missing + 1
			C_Item.RequestLoadItemDataByID(itemID)
		end
	end
	return value, missing
end

local function price(section)
	local value, missing = Items:VendorValue(section.items)
	section.vendorValue = value
	unpriced[section] = missing > 0 or nil
end

--- Scan the given containers into `section` (items, slots, vendorValue) and Touch it.
function Items:Record(section, bagIDs)
	local items, total, free = {}, 0, 0
	for _, bagID in ipairs(bagIDs) do
		local numSlots = C_Container.GetContainerNumSlots(bagID) or 0
		total = total + numSlots
		for slot = 1, numSlots do
			local info = C_Container.GetContainerItemInfo(bagID, slot)
			if info and info.itemID then
				items[info.itemID] = (items[info.itemID] or 0) + (info.stackCount or 1)
			else
				free = free + 1
			end
		end
	end
	section.items = items
	section.slots = { total = total, free = free }
	price(section)
	ns.DB:Touch(section)
end

ns:On("GET_ITEM_INFO_RECEIVED", function()
	if not next(unpriced) then
		return
	end
	ns:Debounce("items.price", 1, function()
		for section in pairs(unpriced) do
			price(section)
			ns.DB:Touch(section)
		end
	end)
end)
