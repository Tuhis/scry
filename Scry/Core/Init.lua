-- Core: namespace, protected calls, event dispatch, module registry.
local addonName, ns = ...

ns.name = addonName
ns.version = C_AddOns.GetAddOnMetadata(addonName, "Version") or "unknown"
ns.modules = {}
ns.moduleOrder = {}

-- Every entry point into addon code (events, timers, slash commands) goes through
-- ns.safecall so that errors are recorded in the dev log (and therefore visible to
-- `./dev report`) before being handed to the game's normal error handler.
local function onError(err)
	local stack = debugstack(2)
	if ns.Log then
		ns.Log:Error(err, stack)
	end
	geterrorhandler()(err)
	return err
end

function ns.safecall(fn, ...)
	return xpcall(fn, onError, ...)
end

-- Events ---------------------------------------------------------------------
local frame = CreateFrame("Frame")
local handlers = {}

frame:SetScript("OnEvent", function(_, event, ...)
	local list = handlers[event]
	if not list then
		return
	end
	for i = 1, #list do
		ns.safecall(list[i], ...)
	end
end)

--- Subscribe to a game event. The handler receives the event payload (not the event name).
function ns:On(event, handler)
	if not handlers[event] then
		handlers[event] = {}
		frame:RegisterEvent(event)
	end
	table.insert(handlers[event], handler)
end

--- Run `fn` after `seconds`, protected.
function ns:After(seconds, fn)
	C_Timer.After(seconds, function()
		ns.safecall(fn)
	end)
end

-- Modules --------------------------------------------------------------------
--- Register a data module. `name` is also the key of the module's section in ScryDB.
--- Optional callbacks: module:OnLogin() - player data is available, DB is ready.
function ns:NewModule(name)
	assert(not self.modules[name], "duplicate module: " .. name)
	local module = { name = name }
	self.modules[name] = module
	table.insert(self.moduleOrder, module)
	return module
end

ns:On("ADDON_LOADED", function(loadedName)
	if loadedName ~= addonName then
		return
	end
	ns.Log:Init()
	ns.DB:Init()
end)

ns:On("PLAYER_LOGIN", function()
	for _, module in ipairs(ns.moduleOrder) do
		if module.OnLogin then
			ns.safecall(module.OnLogin, module)
		end
	end
	ns.Log:Info("login complete, modules: " .. #ns.moduleOrder)
	if ns.Log:IsDev() then
		ns:After(2, function()
			ns.SelfTest:Run(true)
		end)
	end
end)
