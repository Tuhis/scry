-- Dev log. Everything here lands in the ScryDevDB SavedVariable, which is how the
-- development tooling (./dev report / ./dev wait) sees what happened in game.
-- ScryDevDB always describes exactly one session: it is reset when the addon loads
-- and written to disk by the game on the next /reload or logout.
-- ScryDevDB is a debugging aid, NOT part of the external data contract (that is ScryDB).
local addonName, ns = ...

local MAX_LOG = 300
local MAX_ERRORS = 50

local Log = {}
ns.Log = Log

local db

local function emptyDevDB(enabled)
	local gameVersion, gameBuild, _, interface = GetBuildInfo()
	return {
		enabled = enabled,
		session = {
			build = ns.build.id,
			addonVersion = ns.version,
			gameVersion = gameVersion,
			gameBuild = gameBuild,
			interface = interface,
			startedAt = GetServerTime(),
		},
		log = {},
		errors = {},
	}
end

function Log:Init()
	local enabled = type(ScryDevDB) == "table" and ScryDevDB.enabled == true
	ScryDevDB = emptyDevDB(enabled)
	db = ScryDevDB

	ns:On("ADDON_ACTION_FORBIDDEN", function(culprit, func)
		if culprit == addonName then
			Log:Error("ADDON_ACTION_FORBIDDEN: " .. tostring(func), "")
		end
	end)
	ns:On("ADDON_ACTION_BLOCKED", function(culprit, func)
		if culprit == addonName then
			Log:Error("ADDON_ACTION_BLOCKED: " .. tostring(func), "")
		end
	end)

	if self:IsDev() then
		-- Also capture errors that do not pass through ns.safecall (e.g. raised
		-- inside widget scripts) by chaining the global error handler.
		local previous = geterrorhandler()
		seterrorhandler(function(err, ...)
			if type(err) == "string" and err:find(addonName, 1, true) then
				Log:Error(err, debugstack(2))
			end
			return previous(err, ...)
		end)
	end
end

--- Dev mode: on for builds made by `./dev deploy`, or toggled with `/scry dev on`.
function Log:IsDev()
	return ns.build.dev or (db ~= nil and db.enabled == true)
end

function Log:SetDev(enabled)
	db.enabled = enabled and true or false
end

local function push(level, message)
	if not db then
		return
	end
	local log = db.log
	log[#log + 1] = { t = GetServerTime(), level = level, msg = tostring(message) }
	if #log > MAX_LOG then
		table.remove(log, 1)
	end
end

function Log:Debug(message)
	if self:IsDev() then
		push("debug", message)
	end
end

function Log:Info(message)
	push("info", message)
end

function Log:Warn(message)
	push("warn", message)
end

--- Record an error. Identical messages are counted instead of repeated.
function Log:Error(message, stack)
	if not db then
		return
	end
	message = tostring(message)
	for _, e in ipairs(db.errors) do
		if e.msg == message then
			e.count = e.count + 1
			return
		end
	end
	if #db.errors < MAX_ERRORS then
		db.errors[#db.errors + 1] = { t = GetServerTime(), msg = message, stack = tostring(stack or ""), count = 1 }
	end
end

function Log:ErrorCount()
	return db and #db.errors or 0
end
