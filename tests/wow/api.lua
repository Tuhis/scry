-- Stubs for the WoW API, backed by wow.state. ADD NEW STUBS HERE.
--
-- Before stubbing anything, look up the real signature and return values:
--   ./dev api <name>            (signatures from Blizzard's API docs)
--   ./dev api --source <name>   (how Blizzard's own UI code uses it)
-- A stub must return what the real client returns (same order, same types,
-- including nil cases). A wrong stub makes tests pass on behaviour the game does
-- not have. Where behaviour is uncertain, also add an in-game selftest
-- (ns.SelfTest:Register) so `./dev report` verifies it against the real client.
--
-- To let tests control what a stub returns, read from wow.state and document the
-- field in default_state() in tests/wow/init.lua.

return function(wow, env)
	local state = wow.state

	-- Lua extensions and aliases the client provides ------------------------------
	env.xpcall = function(fn, handler, ...) -- WoW's xpcall forwards extra arguments
		local args, n = { ... }, select("#", ...)
		return xpcall(function()
			return fn(unpack(args, 1, n))
		end, handler)
	end
	env.print = function(...)
		local parts = {}
		for i = 1, select("#", ...) do
			parts[i] = tostring((select(i, ...)))
		end
		wow.printed[#wow.printed + 1] = table.concat(parts, " ")
	end
	env.format = string.format
	env.strfind, env.strmatch, env.strsub, env.strlen = string.find, string.match, string.sub, string.len
	env.strlower, env.strupper, env.strrep, env.gsub = string.lower, string.upper, string.rep, string.gsub
	env.strtrim = function(s)
		return (s:gsub("^%s+", ""):gsub("%s+$", ""))
	end
	env.strsplit = function(delimiter, s, pieces)
		local out, start = {}, 1
		while true do
			local i = (not pieces or #out < pieces - 1) and s:find(delimiter, start, true)
			if not i then
				out[#out + 1] = s:sub(start)
				break
			end
			out[#out + 1] = s:sub(start, i - 1)
			start = i + #delimiter
		end
		return unpack(out)
	end
	env.strjoin = function(delimiter, ...)
		return table.concat({ ... }, delimiter)
	end
	env.tinsert, env.tremove, env.sort = table.insert, table.remove, table.sort
	env.wipe = function(t)
		for k in pairs(t) do
			t[k] = nil
		end
		return t
	end
	env.tContains = function(t, value)
		for _, v in pairs(t) do
			if v == value then
				return true
			end
		end
		return false
	end
	env.floor, env.ceil, env.min, env.max, env.abs = math.floor, math.ceil, math.min, math.max, math.abs
	env.date = os.date
	env.time = function()
		return state.time
	end
	env.debugstack = function()
		return debug.traceback("", 2)
	end
	env.geterrorhandler = function()
		return wow.errorHandler
	end
	env.seterrorhandler = function(handler)
		wow.errorHandler = handler
	end

	-- Client / session ---------------------------------------------------------
	env.GetTime = function()
		return state.uptime
	end
	env.GetServerTime = function()
		return state.time
	end
	env.GetLocale = function()
		return state.locale
	end
	env.GetBuildInfo = function()
		local b = state.build
		return b.version, b.number, b.date, b.interface, b.version, ""
	end
	env.ReloadUI = function()
		wow.reloadRequested = true -- tests call wow:reload() to actually perform it
	end
	env.Screenshot = function()
		wow.screenshots = wow.screenshots + 1
	end
	env.SlashCmdList = {}
	env.CreateFrame = function(frameType, name)
		return wow:_createFrame(frameType, name)
	end
	env.C_Timer = wow:namespace("C_Timer", {
		After = function(seconds, fn)
			wow.timers[#wow.timers + 1] = { at = state.uptime + seconds, fn = fn }
		end,
	})
	env.C_AddOns = wow:namespace("C_AddOns", {
		GetAddOnMetadata = function(name, field)
			if name == wow.addonName and wow.toc then
				return wow.toc.meta[field]
			end
			return nil
		end,
	})

	-- Realm --------------------------------------------------------------------
	env.GetRealmName = function()
		return state.realm.name
	end
	env.GetNormalizedRealmName = function()
		return state.realm.normalized
	end

	-- Units (only "player" is modelled so far) -----------------------------------
	local function player(unit)
		return unit == "player" and state.player or nil
	end
	env.UnitName = function(unit)
		local p = player(unit)
		return p and p.name, nil
	end
	env.UnitGUID = function(unit)
		local p = player(unit)
		return p and p.guid
	end
	env.UnitClass = function(unit)
		local p = player(unit)
		if p then
			return p.class.name, p.class.token, p.class.id
		end
	end
	env.UnitRace = function(unit)
		local p = player(unit)
		if p then
			return p.race.name, p.race.token, p.race.id
		end
	end
	env.UnitFactionGroup = function(unit)
		local p = player(unit)
		if p then
			return p.faction, p.faction
		end
	end
	env.UnitLevel = function(unit)
		local p = player(unit)
		return p and p.level or 0
	end
end
