local Wow = require("tests.wow")

describe("module: character", function()
	it("records the player on login", function()
		local wow = Wow.new({
			player = {
				name = "Thrall",
				level = 70,
				faction = "Horde",
				class = { token = "SHAMAN" },
				race = { token = "Orc" },
			},
		}):login()
		wow:assertNoErrors()
		local c = wow.env.ScryDB.characters["Player-1234-0ABCDEF0"].character
		assert.same({
			name = "Thrall",
			class = "SHAMAN",
			race = "Orc",
			faction = "Horde",
			level = 70,
			guid = "Player-1234-0ABCDEF0",
			sex = "female",
			xp = 1500,
			xpMax = 20000,
			restedXp = 300,
			zone = 1453,
			bindLocation = "Stormwind City",
			hardcore = false,
			experiencePreset = "enhanced",
			updatedAt = 1700000000,
		}, c)
	end)

	it("records guild membership and copes with missing optional data", function()
		local wow = Wow.new({
			player = {
				guild = { name = "Scryers", rankName = "Officer", rankIndex = 1 },
				restedXp = false,
				zone = false,
				experiencePreset = false,
				hardcore = true,
				sex = 0,
			},
		}):login()
		wow:assertNoErrors()
		local c = wow.env.ScryDB.characters["Player-1234-0ABCDEF0"].character
		assert.same({ name = "Scryers", rank = "Officer", rankIndex = 1 }, c.guild)
		assert.equals(0, c.restedXp)
		assert.is_nil(c.zone)
		assert.is_nil(c.experiencePreset)
		assert.is_true(c.hardcore)
		assert.equals("male", c.sex)

		wow.state.player.guild = false
		wow.state.player.xp = 1600
		wow:fire("PLAYER_GUILD_UPDATE", "player")
		assert.is_nil(c.guild)
		assert.equals(1600, c.xp)
	end)

	it("updates the level from the PLAYER_LEVEL_UP payload", function()
		local wow = Wow.new({ player = { level = 10 } }):login()
		wow:advance(60)
		wow:fire("PLAYER_LEVEL_UP", 11) -- UnitLevel still returns the old level at this point
		wow:assertNoErrors()
		local c = wow.env.ScryDB.characters["Player-1234-0ABCDEF0"].character
		assert.equals(11, c.level)
		assert.equals(1700000060, c.updatedAt)
		assert.equals(1700000060, wow.env.ScryDB.meta.updatedAt)
	end)

	it("keeps one entry per character", function()
		local wow = Wow.new():login()
		local saved = wow:logout()
		local alt = Wow.new({ saved = saved, player = { name = "Alt", guid = "Player-1234-0ABCDEF1" } }):login()
		alt:assertNoErrors()
		assert.is_table(alt.env.ScryDB.characters["Player-1234-0ABCDEF0"])
		assert.is_table(alt.env.ScryDB.characters["Player-1234-0ABCDEF1"])
	end)
end)
