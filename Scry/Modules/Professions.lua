-- Module "professions": the exact recipes known, per profession. The recipe list
-- is only available while that profession's window is open, so each profession
-- is a snapshot taken when the player last opened it. Skill levels are in "skills".
local _, ns = ...

local Professions = ns:NewModule("professions")

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
			ns.DB:Name("spells", recipeID, recipe.name)
		end
	end
	table.sort(recipes)
	local section, list = known()
	list[professionID] = { recipes = recipes, scannedAt = GetServerTime() }
	ns.DB:Name("skills", professionID, info.professionName)
	ns.DB:Touch(section)
	ns.Log:Debug(("professions: %s scanned, %d of %d recipes known"):format(professionID, #recipes, #all))
end

-- Recipe lists saved before ScryDB.names existed (or while a name was not loaded)
-- have no names, and are only rescanned when their window is opened again. A
-- recipe ID is a spell ID, so name the stored recipes from the spell data.
function Professions:OnLogin()
	local section = ns.DB:Peek("professions")
	local names = ns.DB.db.names.spells
	for _, entry in pairs(section and section.known or {}) do
		for _, recipeID in ipairs(entry.recipes) do
			if not names[recipeID] then
				ns.DB:Name("spells", recipeID, C_Spell.GetSpellName(recipeID))
			end
		end
	end
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
	local recipe = C_TradeSkillUI.GetRecipeInfo(recipeID)
	ns.DB:Name("spells", recipeID, recipe and recipe.name)
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

-- OnLogin names stored recipes by C_Spell.GetSpellName. That relies on a recipe ID
-- being the ID of a spell with the recipe's name; check it against the recipe API
-- while a profession window is open.
ns.SelfTest:Register("professions: recipe names match their spell names (with a profession window open)", function()
	if not C_TradeSkillUI.IsTradeSkillReady() then
		return
	end
	local checked = 0
	for _, recipeID in ipairs(C_TradeSkillUI.GetAllRecipeIDs() or {}) do
		local recipe = C_TradeSkillUI.GetRecipeInfo(recipeID)
		if recipe and recipe.name and checked < 50 then
			checked = checked + 1
			local spellName = C_Spell.GetSpellName(recipeID)
			assert(
				spellName == recipe.name,
				("recipe %d is %q, spell %d is %q"):format(recipeID, recipe.name, recipeID, tostring(spellName))
			)
		end
	end
end)
