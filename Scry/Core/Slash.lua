local _, ns = ...

local commands = {}

commands.selftest = function()
	ns.SelfTest:Run(false)
end

commands.status = function()
	print(
		("Scry %s (build %s, dev %s), %d error(s) this session"):format(
			ns.version,
			ns.build.id,
			ns.Log:IsDev() and "on" or "off",
			ns.Log:ErrorCount()
		)
	)
end

commands.dev = function(arg)
	if arg == "on" or arg == "off" then
		ns.Log:SetDev(arg == "on")
	end
	print("Scry dev mode: " .. (ns.Log:IsDev() and "on" or "off"))
end

-- Reloading writes SavedVariables to disk, which is what hands data to external
-- apps and to the dev tooling.
commands.rl = function()
	ReloadUI()
end

commands.shot = function()
	Screenshot()
end

local function help()
	print("Scry commands: /scry status | selftest | dev on|off | rl | shot")
end

SLASH_SCRY1 = "/scry"
SlashCmdList.SCRY = function(input)
	local name, arg = strtrim(input or ""):match("^(%S*)%s*(.-)$")
	local command = commands[name:lower()]
	if command then
		ns.safecall(command, arg)
	else
		help()
	end
end
