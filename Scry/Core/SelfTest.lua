-- In-game self tests. These verify assumptions about the REAL client that the
-- offline mocks cannot (does this API exist, does it return what we expect?).
-- Results are stored in ScryDevDB.selftest and read by `./dev report`.
local _, ns = ...

local SelfTest = { tests = {} }
ns.SelfTest = SelfTest

--- Register a test. `fn` passes when it returns without raising an error.
function SelfTest:Register(name, fn)
	table.insert(self.tests, { name = name, fn = fn })
end

function SelfTest:Run(quiet)
	local results, failed = {}, 0
	for _, test in ipairs(self.tests) do
		local ok, err = pcall(test.fn)
		if not ok then
			failed = failed + 1
		end
		results[#results + 1] = { name = test.name, ok = ok, msg = ok and "" or tostring(err) }
	end
	ScryDevDB.selftest = { ranAt = GetServerTime(), total = #results, failed = failed, results = results }
	if failed > 0 or not quiet then
		print(("Scry selftest: %d/%d passed"):format(#results - failed, #results))
		for _, r in ipairs(results) do
			if not r.ok then
				print("  FAIL " .. r.name .. ": " .. r.msg)
			end
		end
	end
	return failed == 0
end

SelfTest:Register("core: ScryDB has the current schema version", function()
	assert(ScryDB.schemaVersion == ns.DB.SCHEMA_VERSION, "schemaVersion is " .. tostring(ScryDB.schemaVersion))
end)

SelfTest:Register("core: character key is well formed", function()
	local key = ns.DB:CharKey()
	assert(type(key) == "string" and key:match("^Player%-%d+%-%x+$"), "unexpected character key: " .. tostring(key))
end)

SelfTest:Register("names: exported IDs have names in the client's language", function()
	local names = ScryDB.names
	assert(names.locale == GetLocale(), "locale: " .. tostring(names.locale))
	-- These are known to the client at login without a server round trip.
	for kind, map in pairs({ spells = names.spells, skills = names.skills, factions = names.factions }) do
		assert(next(map) ~= nil, "no " .. kind .. " names recorded")
	end
	local spells = ns.DB:Section("spells").player or {}
	for spellID in pairs(spells) do
		assert(names.spells[spellID], "spell without a name: " .. spellID)
	end
end)
