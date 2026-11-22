-- Module "professions": the exact recipes known, per profession. The recipe list
-- is only available while that profession's window is open, so each profession
-- is a snapshot taken when the player last opened it. Skill levels are in "skills".
local _, ns = ...

ns:NewModule("professions")

local function known()
	local section = ns.DB:Section("professions")
	section.known = section.known or {}
	return section, section.known
end

local function scan()
	if not C_TradeSkillUI.IsTradeSkillReady() then
		return
	end
	-- Someone else's profession (chat link, guild member) or an NPC crafting window.
	if C_TradeSkillUI.IsTradeSkillLinked() or C_TradeSkillUI.IsTradeSkillGuild() or C_TradeSkillUI.IsNPCCrafting() then
		return
	end
	local info = C_TradeSkillUI.GetBaseProfessionInfo()
	local professionID = info and info.professionID
	if not professionID or professionID == 0 then
		return
	end
	local all = C_TradeSkillUI.GetAllRecipeIDs() or {}
	local recipes = {}
	for _, recipeID in ipairs(all) do
		local recipe = C_TradeSkillUI.GetRecipeInfo(recipeID)
		if recipe and recipe.learned then
			recipes[#recipes + 1] = recipeID
		end
	end
	table.sort(recipes)
	local section, list = known()
	list[professionID] = { recipes = recipes, scannedAt = GetServerTime() }
	ns.DB:Touch(section)
	ns.Log:Debug(("professions: %s scanned, %d of %d recipes known"):format(professionID, #recipes, #all))
end

ns:On("TRADE_SKILL_LIST_UPDATE", function()
	ns:Debounce("professions.scan", 0.5, scan)
end)

ns:On("NEW_RECIPE_LEARNED", function(recipeID)
	local info = C_TradeSkillUI.GetProfessionInfoByRecipeID(recipeID)
	local professionID = info and (info.parentProfessionID or info.professionID)
	local section, list = known()
	local entry = professionID and list[professionID]
	if not entry then
		return -- never scanned: a one-recipe list would look like a complete one
	end
	for _, id in ipairs(entry.recipes) do
		if id == recipeID then
			return
		end
	end
	table.insert(entry.recipes, recipeID)
	table.sort(entry.recipes)
	ns.DB:Touch(section)
end)

ns.SelfTest:Register("professions: scanned professions have recipes (after opening one)", function()
	local s = ns.DB:Peek("professions")
	if not s then
		return -- no profession window opened yet with the addon
	end
	for professionID, entry in pairs(s.known) do
		assert(#entry.recipes > 0, "profession " .. professionID .. " scanned with 0 known recipes")
	end
end)
