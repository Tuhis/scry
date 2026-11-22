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
			updatedAt = 1700000000,
		}, c)
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
