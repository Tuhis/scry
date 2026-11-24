-- Specs for the character profile modules (everything except "character").
local Wow = require("tests.wow")

local KEY = "Player-1234-0ABCDEF0"

local function char(wow)
	return wow.env.ScryDB.characters[KEY]
end

local function login(opts)
	local wow = Wow.new(opts):login()
	wow:assertNoErrors()
	return wow
end

describe("core: ns:Debounce", function()
	it("runs once per burst", function()
		local wow = login()
		local runs = 0
		for _ = 1, 3 do
			wow.ns:Debounce("test", 1, function()
				runs = runs + 1
			end)
		end
		wow:advance(2)
		assert.equals(1, runs)
		wow.ns:Debounce("test", 1, function()
			runs = runs + 1
		end)
		wow:advance(2)
		assert.equals(2, runs)
	end)
end)

describe("module: money", function()
	it("records copper on login and when it changes", function()
		local wow = login({ money = 50 })
		assert.equals(50, char(wow).money.copper)
		wow.state.money = 75
		wow:advance(10)
		wow:fire("PLAYER_MONEY")
		assert.same({ copper = 75, updatedAt = 1700000010 }, char(wow).money)
	end)
end)

describe("module: bags", function()
	it("adds stacks up per item and values them at vendor price", function()
		local wow = login()
		assert.same({
			items = { [6948] = 1, [2589] = 24, [2318] = 10 },
			slots = { total = 22, free = 18 },
			vendorValue = 24 * 13 + 10 * 15,
			updatedAt = 1700000000,
		}, char(wow).bags)
	end)

	it("rescans when the bags change", function()
		local wow = login()
		wow.state.bags[0].slots[2] = nil
		wow:fire("BAG_UPDATE_DELAYED")
		assert.equals(4, char(wow).bags.items[2589])
		assert.equals(19, char(wow).bags.slots.free)
	end)

	it("prices items once the client has loaded their data", function()
		local wow = login({ items = { [2318] = { cached = false } } })
		assert.equals(24 * 13, char(wow).bags.vendorValue)
		assert.same({ 2318 }, wow.itemRequests)
		wow.state.items[2318].cached = true
		wow:fire("GET_ITEM_INFO_RECEIVED", 2318, true)
		wow:advance(2)
		wow:assertNoErrors()
		assert.equals(24 * 13 + 10 * 15, char(wow).bags.vendorValue)
	end)
end)

describe("module: bank", function()
	it("records nothing until the bank is opened", function()
		local wow = login()
		wow:fire("BAG_UPDATE_DELAYED")
		assert.is_nil(char(wow).bank)
	end)

	it("snapshots the bank tabs while the bank is open", function()
		local wow = login()
		wow:fire("BANKFRAME_OPENED")
		wow:assertNoErrors()
		assert.same({
			items = { [2589] = 40 },
			slots = { total = 98, free = 97 },
			vendorValue = 40 * 13,
			updatedAt = 1700000000,
		}, char(wow).bank)

		wow.state.bags[6].slots[4] = { id = 2318, count = 2 }
		wow:fire("BAG_UPDATE_DELAYED")
		assert.equals(2, char(wow).bank.items[2318])

		wow:fire("BANKFRAME_CLOSED")
		wow.state.bags[6].slots[4] = nil
		wow:fire("BAG_UPDATE_DELAYED")
		assert.equals(2, char(wow).bank.items[2318]) -- the snapshot is kept
	end)
end)

describe("module: skills", function()
	it("lists skill lines without headers", function()
		local wow = login()
		assert.same({
			[171] = { rank = 150, maxRank = 225 },
			[43] = { rank = 300, maxRank = 400 },
		}, char(wow).skills.lines)
		wow.state.skills[2].rank = 151
		wow:fire("SKILL_LINES_CHANGED")
		assert.equals(151, char(wow).skills.lines[171].rank)
	end)
end)

describe("module: professions", function()
	local function open(wow)
		wow.state.tradeskill.ready = true
		wow:fire("TRADE_SKILL_LIST_UPDATE")
		wow:advance(1)
		wow:assertNoErrors()
	end

	it("has no data until a profession window was opened", function()
		local wow = login()
		wow:fire("TRADE_SKILL_LIST_UPDATE") -- fires while the window is still loading
		wow:advance(1)
		assert.is_nil(char(wow).professions)
	end)

	it("records the learned recipes of the open profession, sorted", function()
		local wow = login()
		open(wow)
		assert.same({
			[171] = {
				recipes = { 2329, 2330 },
				difficulty = { [2329] = "trivial", [2330] = "easy" },
				scannedAt = 1700000000,
			},
		}, char(wow).professions.known)
	end)

	it("leaves out the difficulty of a recipe the client reports none for", function()
		local wow = login()
		wow.state.tradeskill.recipeDifficulty[2330] = nil
		open(wow)
		assert.same({ [2329] = "trivial" }, char(wow).professions.known[171].difficulty)
	end)

	it("maps learned recipes to their skill line ability IDs", function()
		local wow = login()
		open(wow)
		assert.same({ [2329] = 15200, [2330] = 15201 }, wow.env.ScryDB.names.skillLineAbilities)
		wow:fire("NEW_RECIPE_LEARNED", 2332)
		assert.equals(15203, wow.env.ScryDB.names.skillLineAbilities[2332])
		assert.equals("optimal", char(wow).professions.known[171].difficulty[2332])
	end)

	local function selftest(wow)
		for recipeID in pairs(wow.state.tradeskill.recipes) do
			wow.state.spellNames[recipeID] = "Recipe " .. recipeID -- a recipe is a spell of the same name
		end
		wow:slash("/scry selftest")
		wow:assertNoErrors()
		local st = wow.env.ScryDevDB.selftest
		assert.equals(0, st.failed, require("tests.util").dump(st.results))
	end

	it("passes its selftests with the scanned profession's window open", function()
		local wow = login({ dev = true })
		open(wow)
		selftest(wow)
	end)

	it("passes its selftests when the client reports no difficulty for a recipe", function()
		local wow = login({ dev = true })
		wow.state.tradeskill.recipeDifficulty[2330] = nil
		open(wow)
		selftest(wow)
	end)

	it("passes its selftests in someone else's window of a scanned profession", function()
		for _, kind in ipairs({ "linked", "guild", "npc" }) do
			local wow = login({ dev = true })
			open(wow)
			wow.state.tradeskill[kind] = true
			wow.state.tradeskill.recipes[2332] = true -- they know a recipe this character does not
			selftest(wow)
		end
	end)

	it("adds a newly learned recipe to a profession saved without difficulties", function()
		local wow = login()
		open(wow)
		char(wow).professions.known[171].difficulty = nil -- as saved by an older version
		wow:fire("NEW_RECIPE_LEARNED", 2332)
		wow:assertNoErrors()
		assert.same({ [2332] = "optimal" }, char(wow).professions.known[171].difficulty)
	end)

	it("ignores linked, guild and NPC crafting windows", function()
		for _, kind in ipairs({ "linked", "guild", "npc" }) do
			local wow = login({ tradeskill = { [kind] = true } })
			open(wow)
			assert.is_nil(char(wow).professions, kind)
		end
	end)

	it("adds newly learned recipes to a scanned profession only", function()
		local wow = login()
		wow:fire("NEW_RECIPE_LEARNED", 2332)
		assert.is_nil(char(wow).professions.known[171])
		open(wow)
		wow:fire("NEW_RECIPE_LEARNED", 2332)
		wow:fire("NEW_RECIPE_LEARNED", 2332)
		wow:assertNoErrors()
		assert.same({ 2329, 2330, 2332 }, char(wow).professions.known[171].recipes)
	end)
end)

describe("module: spells", function()
	it("records learned spells with rank and passive flag", function()
		local wow = login()
		assert.same({
			[6603] = { passive = false },
			[133] = { passive = false, rank = 1 },
			[143] = { passive = false, rank = 2 },
			[11103] = { passive = true },
		}, char(wow).spells.player)
		assert.is_nil(char(wow).spells.pet)
	end)

	it("falls back to the spell subtext when the spellbook has none yet", function()
		local wow = login({ spellSubtext = { [6603] = "Rank 4" } })
		assert.equals(4, char(wow).spells.player[6603].rank)
	end)

	it("keeps the pet's spells after the pet is gone", function()
		local wow = login({ spellbook = { pet = { { spellID = 17253, name = "Bite", subName = "Rank 3" } } } })
		assert.same({ [17253] = { passive = false, rank = 3 } }, char(wow).spells.pet)
		wow.state.spellbook.pet = false
		wow:fire("SPELLS_CHANGED")
		wow:advance(2)
		wow:assertNoErrors()
		assert.is_table(char(wow).spells.pet[17253])
	end)
end)

describe("module: legacy", function()
	it("records points and purchased tree nodes on login", function()
		local wow = login()
		local legacy = char(wow).legacy
		assert.same({ earned = 7, max = 50, unspent = 3, spent = 4 }, legacy.points)
		assert.same({ [1187] = { [5001] = 1 }, [1188] = { [5101] = 3 }, [1189] = {} }, legacy.trees)
		assert.is_nil(legacy.challenges)
	end)

	it("records completed challenges a few seconds after login", function()
		local wow = login()
		wow:advance(6)
		wow:assertNoErrors()
		assert.same({
			[9001] = { earnedByMe = true, points = 10, date = "2026-11-22" },
			[9003] = { earnedByMe = false, points = 0, date = "2026-01-05" },
		}, char(wow).legacy.challenges)
	end)

	it("updates when a challenge is completed or points are spent", function()
		local wow = login()
		wow:advance(6)
		local a = wow.state.achievements[1].list[2]
		a.completed, a.month, a.day, a.year, a.earnedByMe = true, 12, 1, 26, true
		wow:fire("ACHIEVEMENT_EARNED", 9002)
		wow.state.traits.trees[1189][5201] = 2
		wow.state.traits.currency.quantity = 1
		wow:fire("TRAIT_CONFIG_UPDATED", 103)
		wow:advance(3)
		wow:assertNoErrors()
		assert.equals("2026-12-01", char(wow).legacy.challenges[9002].date)
		assert.equals(2, char(wow).legacy.trees[1189][5201])
		assert.equals(1, char(wow).legacy.points.unspent)
	end)

	it("copes with trees the client has no config for", function()
		local wow = login({ traits = { treeConfigs = { [1188] = false, [1189] = false } } })
		assert.is_table(char(wow).legacy.trees[1187])
		assert.is_nil(char(wow).legacy.trees[1188])
	end)
end)

describe("module: equipment", function()
	it("records equipped items by slot", function()
		local wow = login()
		assert.same({
			[1] = { itemID = 10504, link = "|cff0070dd|Hitem:10504::::::::80:::::|h[Green Lens]|h|r" },
			[16] = { itemID = 2092, link = "|cffffffff|Hitem:2092:7:::::::80:::::|h[Worn Dagger]|h|r" },
		}, char(wow).equipment.slots)
		wow.state.equipment[16] = nil
		wow:fire("PLAYER_EQUIPMENT_CHANGED", 16, true)
		wow:advance(1)
		assert.is_nil(char(wow).equipment.slots[16])
	end)
end)

describe("module: talents", function()
	it("records spec, talent nodes and the loadout string", function()
		local wow = login()
		local talents = char(wow).talents
		assert.equals(63, talents.specID)
		assert.same({ [7001] = 5, [7003] = 2 }, talents.nodes)
		assert.equals("CAEAAAAAAAAAAAAAAAAAAAAAAA", talents.loadout)
	end)

	it("copes with a character without talents", function()
		local wow = login({ traits = { activeClassConfig = false }, spec = { index = 0 } })
		assert.same({}, char(wow).talents.nodes)
		assert.is_nil(char(wow).talents.specID)
		assert.is_nil(char(wow).talents.loadout)
	end)
end)

describe("modules: reputations, currencies, quests, pvp, played", function()
	it("records them on login", function()
		local wow = login()
		local c = char(wow)
		assert.same(
			{ [72] = { standing = 5, value = 4200 }, [47] = { standing = 4, value = 900 } },
			c.reputations.factions
		)
		assert.same({ [3485] = 12 }, c.currencies.amounts)
		assert.same({ 7, 54, 783 }, c.quests.completed)
		assert.same({ honorableKills = 12, highestRank = 0, updatedAt = 1700000000 }, c.pvp)
		assert.is_nil(c.played)
	end)

	it("follows changes", function()
		local wow = login()
		wow.state.reputations[2].currentStanding = 4300
		wow:fire("UPDATE_FACTION")
		wow.state.currencies[2].quantity = 13
		wow:fire("CURRENCY_DISPLAY_UPDATE", 3485, 13, 1)
		table.insert(wow.state.quests, 100)
		wow:fire("QUEST_TURNED_IN", 100, 0, 0)
		wow:fire("TIME_PLAYED_MSG", 360000, 1200)
		wow:advance(3)
		wow:assertNoErrors()
		local c = char(wow)
		assert.equals(4300, c.reputations.factions[72].value)
		assert.equals(13, c.currencies.amounts[3485])
		assert.same({ 7, 54, 100, 783 }, c.quests.completed)
		assert.same({ total = 360000, thisLevel = 1200, updatedAt = 1700000000 }, c.played)
	end)
end)
