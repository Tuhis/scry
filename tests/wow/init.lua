-- Offline simulation of the WoW addon environment, just enough to load the real
-- addon from its TOC and drive it through login / events / reload / logout.
--
--   local Wow = require("tests.wow")
--   local wow = Wow.new({ player = { name = "Thrall", level = 70 } })
--   wow:login()                       -- loads Scry/*.lua per the TOC, fires login events
--   wow:fire("PLAYER_LEVEL_UP", 71)   -- any game event (name is validated)
--   wow:advance(5)                    -- moves the clock, runs C_Timer callbacks
--   wow:slash("/scry status")
--   wow:reload()                      -- logout + SavedVariables round trip + login
--   wow.env.ScryDB / wow.ns / wow.printed / wow.errors
--   wow:assertNoErrors()
--
-- Game state lives in wow.state (see defaults below); API stubs in tests/wow/api.lua
-- read from it. Fidelity rules:
--   * Reading a global that is real WoW API but has no stub raises an error telling
--     you to add one (never silently nil).
--   * Registering an event that does not exist raises an error, as in game.
--   * Errors inside handlers go to the error handler and are collected in
--     wow.errors, as in game - they do not propagate into the test.
--   * SavedVariables are serialised to text and re-parsed on reload, so only what
--     the real client would persist survives.

local serialize = require("tests.wow.serialize")
local install_api = require("tests.wow.api")

local api_dir = os.getenv("WOW_API_DIR")
assert(api_dir, "WOW_API_DIR is not set: run tests through ./dev test (they need the toolchain container)")
local real_api = dofile(api_dir .. "/api.lua")

local Wow = {}
Wow.__index = Wow
Wow.real_api = real_api

local function deep_merge(dst, src)
	for k, v in pairs(src or {}) do
		if type(v) == "table" and type(dst[k]) == "table" then
			deep_merge(dst[k], v)
		else
			dst[k] = v
		end
	end
	return dst
end

local function default_state()
	return {
		time = 1700000000, -- unix seconds (GetServerTime / time)
		uptime = 1000, -- seconds (GetTime)
		locale = "enUS",
		build = { version = "1.60.1", number = "71037", date = "Nov 1 2026", interface = 16001 },
		realm = { name = "", normalized = "" }, -- WoW: Forever has no realms: both APIs return ""
		player = {
			name = "Tester",
			guid = "Player-1234-0ABCDEF0",
			class = { name = "Mage", token = "MAGE", id = 8 },
			race = { name = "Human", token = "Human", id = 1 },
			faction = "Alliance",
			level = 80,
		},
	}
end

--- opts: any wow.state fields to override, plus
---   addonDir (default "Scry"), dev (bool: pretend this is a `./dev deploy` build),
---   saved (SavedVariables file text from a previous session)
function Wow.new(opts)
	opts = opts or {}
	local self = setmetatable({}, Wow)
	self.addonDir = opts.addonDir or "Scry"
	self.addonName = self.addonDir:match("([^/]+)$")
	self.dev = opts.dev or false
	self.saved = opts.saved
	self.state = default_state()
	for k, v in pairs(opts) do
		if self.state[k] ~= nil then
			if type(v) == "table" then
				deep_merge(self.state[k], v)
			else
				self.state[k] = v
			end
		end
	end
	self.errors = {}
	self.printed = {}
	self.reloadRequested = false
	self.screenshots = 0
	self:_reset()
	return self
end

-- ------------------------------------------------------------------ environment
local lua_globals = {
	"assert",
	"error",
	"ipairs",
	"pairs",
	"next",
	"select",
	"tostring",
	"tonumber",
	"type",
	"unpack",
	"pcall",
	"rawget",
	"rawset",
	"rawequal",
	"setmetatable",
	"getmetatable",
	"string",
	"table",
	"math",
	"loadstring",
	"setfenv",
	"getfenv",
	"coroutine",
}

function Wow:_reset()
	self.frames = {}
	self.timers = {}
	self.ns = {}
	self.loggedIn = false
	local env = {}
	for _, name in ipairs(lua_globals) do
		env[name] = _G[name]
	end
	env._G = env
	self.env = env
	self.errorHandler = function(err)
		self.errors[#self.errors + 1] = tostring(err)
	end
	install_api(self, env)
	setmetatable(env, {
		__index = function(_, key)
			if type(key) == "string" and real_api.globals[key] then
				error(
					("WoW API '%s' is real but has no stub yet. Look it up (./dev api '%s') and add a stub to tests/wow/api.lua"):format(
						key,
						key
					),
					2
				)
			end
			return nil
		end,
	})
end

--- Build a namespace table (C_Foo) that errors on real-but-unstubbed members.
function Wow:namespace(name, members)
	local known = real_api.globals[name]
	return setmetatable(members, {
		__index = function(_, key)
			if type(known) == "table" and known[key] then
				error(
					("WoW API '%s.%s' is real but has no stub yet. Look it up (./dev api '%s.%s') and add a stub to tests/wow/api.lua"):format(
						name,
						key,
						name,
						key
					),
					2
				)
			end
			return nil
		end,
	})
end

-- Run fn the way the game runs addon code: errors go to the error handler.
function Wow:_protected(fn, ...)
	local args, n = { ... }, select("#", ...)
	return xpcall(function()
		return fn(unpack(args, 1, n))
	end, function(err)
		local handler = self.errorHandler
		local ok, herr = pcall(handler, err)
		if not ok then
			self.errors[#self.errors + 1] = "error in error handler: " .. tostring(herr)
		end
		return err
	end)
end

-- ----------------------------------------------------------------------- frames
local Frame = {}
Frame.__index = function(_, key)
	local method = rawget(Frame, key)
	if method then
		return method
	end
	error(
		("widget method '%s' has no stub yet. Look it up (./dev api ':%s') and add it to Frame in tests/wow/init.lua"):format(
			key,
			key
		),
		2
	)
end

function Frame:RegisterEvent(event)
	if not real_api.events[event] then
		error(('Frame:RegisterEvent(): Attempt to register unknown event "%s"'):format(tostring(event)), 2)
	end
	self.__events[event] = true
	return true
end
function Frame:UnregisterEvent(event)
	self.__events[event] = nil
end
function Frame:UnregisterAllEvents()
	self.__events = {}
end
function Frame:IsEventRegistered(event)
	return self.__events[event] == true
end
function Frame:SetScript(script, handler)
	self.__scripts[script] = handler
end
function Frame:GetScript(script)
	return self.__scripts[script]
end
function Frame:Show()
	self.__shown = true
end
function Frame:Hide()
	self.__shown = false
end
function Frame:IsShown()
	return self.__shown
end
function Frame:GetName()
	return self.__name
end

function Wow:_createFrame(frameType, name)
	local frame =
		setmetatable({ __type = frameType, __name = name, __events = {}, __scripts = {}, __shown = true }, Frame)
	self.frames[#self.frames + 1] = frame
	if name then
		self.env[name] = frame
	end
	return frame
end

-- ------------------------------------------------------------------- driving it
--- Fire a game event at every frame registered for it.
function Wow:fire(event, ...)
	assert(
		real_api.events[event],
		"wow:fire(): unknown event " .. tostring(event) .. " (./dev api " .. tostring(event) .. ")"
	)
	for _, frame in ipairs({ unpack(self.frames) }) do
		local handler = frame.__events[event] and frame.__scripts.OnEvent
		if handler then
			self:_protected(handler, frame, event, ...)
		end
	end
end

--- Advance the clock by `seconds`, running due C_Timer callbacks in order.
function Wow:advance(seconds)
	local target = self.state.uptime + seconds
	while true do
		local best
		for i, t in ipairs(self.timers) do
			if t.at <= target and (not best or t.at < self.timers[best].at) then
				best = i
			end
		end
		if not best then
			break
		end
		local timer = table.remove(self.timers, best)
		self.state.time = self.state.time + (timer.at - self.state.uptime)
		self.state.uptime = timer.at
		if not timer.cancelled then
			self:_protected(timer.fn)
		end
	end
	self.state.time = self.state.time + (target - self.state.uptime)
	self.state.uptime = target
end

--- Type a slash command, e.g. wow:slash("/scry status").
function Wow:slash(text)
	local cmd, rest = text:match("^(/%S+)%s*(.*)$")
	assert(cmd, "not a slash command: " .. text)
	for key, handler in pairs(self.env.SlashCmdList) do
		local i = 1
		while rawget(self.env, "SLASH_" .. key .. i) do
			if rawget(self.env, "SLASH_" .. key .. i):lower() == cmd:lower() then
				self:_protected(handler, rest)
				return
			end
			i = i + 1
		end
	end
	error("no such slash command: " .. cmd)
end

local function parse_toc(path)
	local toc = { files = {}, meta = {} }
	for line in assert(io.lines(path)) do
		line = line:gsub("\r$", "")
		local key, value = line:match("^##%s*([^:]+):%s*(.-)%s*$")
		if key then
			toc.meta[key] = value
		elseif not line:match("^%s*#") and line:match("%S") then
			toc.files[#toc.files + 1] = (line:gsub("\\", "/"):gsub("^%s+", ""):gsub("%s+$", ""))
		end
	end
	toc.savedVariables = {}
	for name in (toc.meta.SavedVariables or ""):gmatch("[%w_]+") do
		toc.savedVariables[#toc.savedVariables + 1] = name
	end
	return toc
end

--- Load the addon and log in. Mirrors the client's order: addon files, then
--- SavedVariables, then ADDON_LOADED, PLAYER_LOGIN, PLAYER_ENTERING_WORLD.
function Wow:login(isReload)
	assert(not self.loggedIn, "already logged in; use wow:reload()")
	self.toc = parse_toc(self.addonDir .. "/" .. self.addonName .. ".toc")
	for _, file in ipairs(self.toc.files) do
		local chunk, err = loadfile(self.addonDir .. "/" .. file)
		if not chunk then
			self.errorHandler(err)
		else
			setfenv(chunk, self.env)
			self:_protected(chunk, self.addonName, self.ns)
		end
		if file == "BuildInfo.lua" and self.dev and self.ns.build then
			self.ns.build.id = "test-dev-build"
			self.ns.build.dev = true
		end
	end
	if self.saved then
		local chunk = assert(loadstring(self.saved, "SavedVariables"))
		setfenv(chunk, self.env)
		chunk()
	end
	self.loggedIn = true
	self:fire("ADDON_LOADED", self.addonName, false)
	self:fire("PLAYER_LOGIN")
	self:fire("PLAYER_ENTERING_WORLD", not isReload, isReload or false)
	return self
end

--- Log out. Returns the SavedVariables file text the client would write.
function Wow:logout()
	assert(self.loggedIn, "not logged in")
	self:fire("PLAYER_LOGOUT")
	self.loggedIn = false
	self.saved = serialize.file(self.env, self.toc.savedVariables)
	return self.saved
end

--- /reload: logout, fresh Lua state, SavedVariables read back from text, login.
function Wow:reload()
	self:logout()
	self:_reset()
	self.reloadRequested = false
	return self:login(true)
end

--- Fail the current test if any Lua error reached the game's error handler.
function Wow:assertNoErrors()
	if #self.errors > 0 then
		error("addon raised " .. #self.errors .. " error(s):\n  " .. table.concat(self.errors, "\n  "), 2)
	end
end

return Wow
