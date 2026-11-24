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
	-- First character: everything the addon can record, including the data that
	-- needs a window (bank, profession) or a player action (/played).
	local wow = Wow.new({
		addonVersion = "0.1.0", -- pinned: the TOC's version changes with every release
		player = { guild = { name = "Scryers", rankName = "Officer", rankIndex = 1 } },
		spellbook = { pet = { { spellID = 17253, name = "Bite", subName = "Rank 3" } } },
	}):login()
	wow:advance(120)
	wow:fire("PLAYER_LEVEL_UP", 81)
	wow:fire("BANKFRAME_OPENED")
	wow:fire("BANKFRAME_CLOSED")
	wow.state.tradeskill.ready = true
	wow:fire("TRADE_SKILL_LIST_UPDATE")
	wow:fire("TIME_PLAYED_MSG", 360000, 1200)
	wow:advance(10)
	local saved = wow:logout()

	local alt = Wow.new({
		addonVersion = "0.1.0",
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
		-- Second character: one without talents, gear or bags beyond the backpack.
		bags = { [0] = { slots = { [2] = false, [5] = false } }, [1] = { size = 0, slots = { [1] = false } } },
		traits = { activeClassConfig = false, trees = { [1187] = { [5001] = 0 }, [1188] = { [5101] = 0 } } },
		spec = { index = 0 },
		equipment = { [1] = false, [16] = false },
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
