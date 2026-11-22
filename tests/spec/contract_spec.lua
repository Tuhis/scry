-- The data contract, as a golden file: tests/golden/Scry.lua is the exact
-- SavedVariables file produced by the canonical scenario below. `./dev check`
-- additionally validates it against schema/ScryDB.schema.json.
--
-- When a change intentionally alters what the addon writes:
--   1. extend the scenario so every kind of data the addon can write shows up,
--   2. update schema/ScryDB.schema.json and docs/DATA_CONTRACT.md,
--   3. run `./dev golden` and review the diff of tests/golden/Scry.lua.
local Wow = require("tests.wow")
local serialize = require("tests.wow.serialize")
local util = require("tests.util")

local GOLDEN = "tests/golden/Scry.lua"

local function scenario()
	local wow = Wow.new():login()
	wow:advance(120)
	wow:fire("PLAYER_LEVEL_UP", 81)
	local saved = wow:logout()

	local alt = Wow.new({
		saved = saved,
		time = 1700003600,
		player = {
			name = "Thrall",
			guid = "Player-1234-0ABCDEF1",
			level = 70,
			faction = "Horde",
			class = { name = "Shaman", token = "SHAMAN", id = 7 },
			race = { name = "Orc", token = "Orc", id = 2 },
		},
	}):login()
	alt:logout()
	-- Only ScryDB is the contract; ScryDevDB is a debugging aid.
	local text = serialize.file(alt.env, { "ScryDB" })
	wow:assertNoErrors()
	alt:assertNoErrors()
	return text
end

describe("data contract", function()
	it("matches the golden SavedVariables file", function()
		local text = scenario()
		if os.getenv("SCRY_UPDATE_GOLDEN") then
			util.write_file(GOLDEN, text)
		end
		local golden = util.read_file(GOLDEN)
		assert.is_truthy(golden, GOLDEN .. " is missing: run ./dev golden")
		assert.equals(golden, text, "SavedVariables output changed. If intended, see the header of this file.")
	end)
end)
