-- Turns on the game's combat log at login (setting "combatLogAtLogin", on by
-- default). Same effect as typing /combatlog. Exports nothing to ScryDB.
local _, ns = ...

local CombatLog = {}
ns.CombatLog = CombatLog

--- Start combat logging unless it is already running. Returns true if it started it.
function CombatLog:Start()
	if C_ChatInfo.IsLoggingCombat() then
		ns.Log:Debug("combat log already on")
		return false
	end
	LoggingCombat(true)
	if not C_ChatInfo.IsLoggingCombat() then
		ns.Log:Warn("LoggingCombat(true) did not turn combat logging on")
		return false
	end
	ns.Log:Info("combat log turned on")
	print("Scry: combat logging turned on. Change this with /scry.")
	return true
end

ns:On("PLAYER_LOGIN", function()
	if ns.Config:Get("combatLogAtLogin") then
		CombatLog:Start()
	end
end)

ns.Config:OnChange("combatLogAtLogin", function(enabled)
	if enabled then
		CombatLog:Start()
	end
end)

ns.SelfTest:Register("combatlog: combat logging is on when the setting is", function()
	if ns.Config:Get("combatLogAtLogin") then
		assert(C_ChatInfo.IsLoggingCombat(), "combatLogAtLogin is on but the combat log is not running")
	end
end)
