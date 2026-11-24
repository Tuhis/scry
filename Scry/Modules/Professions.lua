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

-- Enum.TradeskillRelativeDifficulty -> exported token: the colour of the recipe in
-- the profession window (orange, yellow, green, grey).
local DIFFICULTY = {
	[Enum.TradeskillRelativeDifficulty.Optimal] = "optimal",
	[Enum.TradeskillRelativeDifficulty.Medium] = "medium",
	[Enum.TradeskillRelativeDifficulty.Easy] = "easy",
	[Enum.TradeskillRelativeDifficulty.Trivial] = "trivial",
}

-- Shared, static data about a learned recipe: its name and skill line ability ID.
local function describe(recipeID, recipe)
	ns.DB:Name("spells", recipeID, recipe.name)
	ns.DB:RecipeAbility(recipeID, recipe.skillLineAbilityID)
end

-- Whether the character's own profession window is open and loaded: not someone
-- else's profession (chat link, guild member) and not an NPC crafting window.
local function ownWindowReady()
	return C_TradeSkillUI.IsTradeSkillReady()
		and not C_TradeSkillUI.IsTradeSkillLinked()
		and not C_TradeSkillUI.IsTradeSkillGuild()
		and not C_TradeSkillUI.IsNPCCrafting()
end

local function scan()
	if not ownWindowReady() then
		return
	end
	local info = C_TradeSkillUI.GetBaseProfessionInfo()
	local professionID = info and info.professionID
	if not professionID or professionID == 0 then
		return
	end
	local all = C_TradeSkillUI.GetAllRecipeIDs() or {}
	local recipes, difficulty = {}, {}
	for _, recipeID in ipairs(all) do
		local recipe = C_TradeSkillUI.GetRecipeInfo(recipeID)
		if recipe and recipe.learned then
			recipes[#recipes + 1] = recipeID
			difficulty[recipeID] = DIFFICULTY[recipe.relativeDifficulty]
			describe(recipeID, recipe)
		end
	end
	table.sort(recipes)
	local section, list = known()
	list[professionID] = { recipes = recipes, difficulty = difficulty, scannedAt = GetServerTime() }
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
	table.sort(entry.recipes)
	local recipe = C_TradeSkillUI.GetRecipeInfo(recipeID)
	if recipe then
		describe(recipeID, recipe)
		entry.difficulty = entry.difficulty or {} -- absent in data saved by older versions
		entry.difficulty[recipeID] = DIFFICULTY[recipe.relativeDifficulty]
	end
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

-- External apps join recipes to Battle.net's recipe documents by skill line
-- ability ID. Check the client reports one for every recipe, that it leads back to
-- the same recipe, and that the scan stored it.
ns.SelfTest:Register("professions: recipes have a skill line ability ID (with a profession window open)", function()
	if not ownWindowReady() then
		return -- scan() stored nothing for this window
	end
	local stored = ns.DB.db.names.skillLineAbilities
	local section = ns.DB:Peek("professions")
	local info = C_TradeSkillUI.GetBaseProfessionInfo()
	local entry = section and info and section.known[info.professionID]
	local checked = 0
	for _, recipeID in ipairs(C_TradeSkillUI.GetAllRecipeIDs() or {}) do
		local recipe = C_TradeSkillUI.GetRecipeInfo(recipeID)
		if recipe and recipe.learned and checked < 50 then
			checked = checked + 1
			local abilityID = recipe.skillLineAbilityID
			assert(
				type(abilityID) == "number" and abilityID > 0,
				("recipe %d has skillLineAbilityID %s"):format(recipeID, tostring(abilityID))
			)
			local back = C_TradeSkillUI.GetRecipeInfoForSkillLineAbility(abilityID)
			assert(
				back and back.recipeID == recipeID,
				("ability %d of recipe %d leads to recipe %s"):format(
					abilityID,
					recipeID,
					tostring(back and back.recipeID)
				)
			)
			if entry then
				assert(
					stored[recipeID] == abilityID,
					("recipe %d: stored ability %s"):format(recipeID, tostring(stored[recipeID]))
				)
				-- The client may report no difficulty (the field is nilable); then none is stored.
				assert(
					not DIFFICULTY[recipe.relativeDifficulty] or (entry.difficulty and entry.difficulty[recipeID]),
					("recipe %d has no difficulty"):format(recipeID)
				)
			end
		end
	end
	-- Known pair from Battle.net: Runed Copper Rod is spell 7421, /data/wow/recipe/4291.
	local rod = C_TradeSkillUI.GetRecipeInfo(7421)
	if rod and rod.skillLineAbilityID then
		assert(rod.skillLineAbilityID == 4291, "Runed Copper Rod (7421) has ability " .. rod.skillLineAbilityID)
	end
end)
