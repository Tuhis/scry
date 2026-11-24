-- Specs for ScryDB.names: the ID -> display name mapping.
local Wow = require("tests.wow")

local function login(opts)
	local wow = Wow.new(opts):login()
	wow:assertNoErrors()
	return wow
end

describe("names", function()
	it("has every kind of name map, also when empty", function()
		local wow = login()
		local names = wow.env.ScryDB.names
		assert.equals("enUS", names.locale)
		for _, kind in ipairs({
			"items",
			"spells",
			"skills",
			"factions",
			"currencies",
			"achievements",
			"traitNodes",
			"maps",
			"specs",
			"quests",
		}) do
			assert.is_table(names[kind], kind)
		end
	end)

	it("names the IDs the modules export", function()
		local wow = login()
		wow:advance(6) -- Legacy Challenges are scanned a few seconds after login
		local names = wow.env.ScryDB.names
		assert.equals("Linen Cloth", names.items[2589]) -- bags
		assert.equals("Green Lens", names.items[10504]) -- equipment
		assert.equals("Fireball", names.spells[143])
		assert.equals("Alchemy", names.skills[171])
		assert.equals("Stormwind", names.factions[72])
		assert.equals("Renown", names.currencies[3485])
		assert.equals("Challenge 9001", names.achievements[9001])
		assert.equals("Master Craftsman", names.traitNodes[5001]) -- Legacy tree node, own name
		assert.equals("Improved Fireball", names.traitNodes[7001]) -- talent node, named after its spell
		assert.is_nil(names.traitNodes[5002]) -- no rank, not exported
		assert.equals("Stormwind City", names.maps[1453])
		assert.equals("Fire", names.specs[63])
		assert.equals("Kobold Camp Cleanup", names.quests[7])
	end)

	it("names recipes and the profession when its window is opened", function()
		local wow = login()
		wow.state.skills = {} -- the profession's name must not depend on the skill list
		wow.env.ScryDB.names.skills = {}
		wow.state.tradeskill.ready = true
		wow:fire("TRADE_SKILL_LIST_UPDATE")
		wow:advance(1)
		wow:assertNoErrors()
		local names = wow.env.ScryDB.names
		assert.equals("Alchemy", names.skills[171])
		assert.equals("Recipe 2330", names.spells[2330])
		assert.is_nil(names.spells[2332]) -- not learned, not exported
		wow:fire("NEW_RECIPE_LEARNED", 2332)
		assert.equals("Recipe 2332", names.spells[2332])
	end)

	it("names recipes saved without names at login, from the spell data", function()
		local wow = login()
		wow.state.tradeskill.ready = true
		wow:fire("TRADE_SKILL_LIST_UPDATE")
		wow:advance(1)
		wow.state.tradeskill.ready = false
		-- As saved by a build before ScryDB.names: the recipe list without names.
		local names = wow.env.ScryDB.names
		names.spells = {}
		wow.state.spellNames[2330] = "Minor Healing Potion"
		wow:reload()
		wow:assertNoErrors()
		names = wow.env.ScryDB.names
		assert.equals("Minor Healing Potion", names.spells[2330])
		-- A name the client already gave is kept; an unknown spell stays unnamed.
		names.spells[2330] = "Recipe 2330"
		wow.state.spellNames[2330] = nil
		wow:reload()
		wow:assertNoErrors()
		assert.equals("Recipe 2330", wow.env.ScryDB.names.spells[2330])
	end)

	it("adds item names once the client has loaded the item", function()
		local wow = login({ items = { [10504] = { cached = false } } })
		local names = wow.env.ScryDB.names
		assert.is_nil(names.items[10504])
		assert.same({ 10504 }, wow.itemRequests)
		wow.state.items[10504].cached = true
		wow:fire("GET_ITEM_INFO_RECEIVED", 10504, true)
		wow:assertNoErrors()
		assert.equals("Green Lens", names.items[10504])
	end)

	it("adds quest titles once the client has loaded the quest", function()
		local wow = login()
		local names = wow.env.ScryDB.names
		assert.is_nil(names.quests[54])
		assert.same({ 54 }, wow.questRequests)
		wow.state.questTitles[54] = "Report to Goldshire"
		wow:fire("QUEST_DATA_LOAD_RESULT", 54, true)
		wow:assertNoErrors()
		assert.equals("Report to Goldshire", names.quests[54])
	end)

	it("is shared by all characters and survives a reload", function()
		local wow = login()
		wow.env.ScryDB.names.items[1] = "Seen On Another Character"
		wow:reload()
		wow:assertNoErrors()
		assert.equals("Seen On Another Character", wow.env.ScryDB.names.items[1])
		assert.equals("Linen Cloth", wow.env.ScryDB.names.items[2589])
	end)

	it("starts over when the client language changes", function()
		local wow = login()
		local saved = wow:logout()
		local german = Wow.new({ saved = saved, locale = "deDE", items = { [2589] = { name = "Leinenstoff" } } })
			:login()
		german:assertNoErrors()
		local names = german.env.ScryDB.names
		assert.equals("deDE", names.locale)
		assert.equals("Leinenstoff", names.items[2589])
	end)

	it("keeps the recipe ability IDs when the client language changes", function()
		local wow = login()
		wow.state.tradeskill.ready = true
		wow:fire("TRADE_SKILL_LIST_UPDATE")
		wow:advance(1)
		local german = Wow.new({ saved = wow:logout(), locale = "deDE" }):login()
		german:assertNoErrors()
		assert.same({ [2329] = 15200, [2330] = 15201 }, german.env.ScryDB.names.skillLineAbilities)
		assert.is_nil(german.env.ScryDB.names.spells[2330])
	end)

	it("has an empty recipe ability map before any profession was opened", function()
		assert.same({}, login().env.ScryDB.names.skillLineAbilities)
	end)
end)
