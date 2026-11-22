-- Guards the fidelity rules of the offline WoW environment itself.
local Wow = require("tests.wow")
local serialize = require("tests.wow.serialize")

describe("test harness", function()
	it("rejects unknown events like the client does", function()
		local wow = Wow.new():login()
		assert.has_error(function()
			wow.ns:On("PLAYER_TOTALLY_MADE_UP", function() end)
		end)
	end)

	it("fails loudly on real API that has no stub", function()
		local wow = Wow.new():login()
		assert.has_error(function()
			return wow.env.GetMoney
		end)
		assert.has_error(function()
			return wow.env.C_Timer.NewTicker
		end)
	end)

	it("returns nil for globals that do not exist in WoW", function()
		local wow = Wow.new():login()
		assert.is_nil(wow.env.ThisIsNotAWowGlobal)
	end)

	it("refuses to persist what the client cannot", function()
		assert.has_error(function()
			serialize.file({ X = { f = function() end } }, { "X" })
		end)
	end)

	it("round-trips SavedVariables text", function()
		local text = serialize.file({ X = { 1, "two", { a = true }, k = 'q"\n', [42] = 1.5 } }, { "X" })
		local env = {}
		setfenv(assert(loadstring(text)), env)()
		assert.same({ 1, "two", { a = true }, k = 'q"\n', [42] = 1.5 }, env.X)
	end)
end)
