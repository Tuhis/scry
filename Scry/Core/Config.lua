-- User settings and the addon's page in the game's Options > AddOns panel (/scry).
-- Settings live in the ScrySettings SavedVariable, one per WoW account. They are
-- NOT part of the data contract (that is ScryDB): they configure the addon only.
local addonName, ns = ...

local Config = { listeners = {} }
ns.Config = Config

-- Every setting, with its default. Saved values of another type are replaced by
-- the default, unknown keys are dropped.
local DEFAULTS = {
	combatLogAtLogin = true,
}
Config.DEFAULTS = DEFAULTS

function Config:Init()
	local saved = type(ScrySettings) == "table" and ScrySettings or {}
	local settings = {}
	for key, default in pairs(DEFAULTS) do
		local value = saved[key]
		if type(value) == type(default) then
			settings[key] = value
		else
			settings[key] = default
		end
	end
	ScrySettings = settings
	self.values = settings
	ns.safecall(self.RegisterPanel, self)
end

function Config:Get(key)
	assert(DEFAULTS[key] ~= nil, "unknown setting: " .. tostring(key))
	return self.values[key]
end

function Config:Set(key, value)
	assert(DEFAULTS[key] ~= nil, "unknown setting: " .. tostring(key))
	assert(type(value) == type(DEFAULTS[key]), "wrong type for setting " .. key)
	if self.values[key] == value then
		return
	end
	self.values[key] = value
	ns.Log:Info(("setting %s = %s"):format(key, tostring(value)))
	for _, fn in ipairs(self.listeners[key] or {}) do
		ns.safecall(fn, value)
	end
end

--- Call `fn(value)` whenever setting `key` is changed (not at load).
function Config:OnChange(key, fn)
	self.listeners[key] = self.listeners[key] or {}
	table.insert(self.listeners[key], fn)
end

-- The settings page ---------------------------------------------------------
-- Built with Blizzard's vertical layout settings API (see Blizzard_ImplementationReadme.lua
-- in Blizzard_Settings_Shared: `./dev api --source RegisterVerticalLayoutCategory`).

local function checkbox(category, key, label, tooltip)
	local setting = Settings.RegisterProxySetting(
		category,
		"SCRY_" .. key:upper(),
		Settings.VarType.Boolean,
		label,
		DEFAULTS[key],
		function()
			return Config:Get(key)
		end,
		function(value)
			ns.safecall(Config.Set, Config, key, value)
		end
	)
	Settings.CreateCheckbox(category, setting, tooltip)
	return setting
end

function Config:RegisterPanel()
	local category, layout = Settings.RegisterVerticalLayoutCategory(addonName)

	layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Combat log"))
	checkbox(
		category,
		"combatLogAtLogin",
		"Turn on combat logging at login",
		"Starts the game's combat log (the same as typing /combatlog) every time you log in or reload, "
			.. "so combat is written to a file in the game's Logs folder for log analysis tools.\n\n"
			.. "Turning this on also starts combat logging right away. Turning it off does not stop "
			.. "a log that is already running: type /combatlog for that."
	)

	-- Optional extra: the page must not depend on it. (In the simulator the Blizzard
	-- file defining CreateSettingsButtonInitializer fails to load; a selftest checks
	-- the real client has it.)
	if CreateSettingsButtonInitializer then
		layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Exported data"))
		layout:AddInitializer(
			CreateSettingsButtonInitializer(
				"Save data now",
				"Reload UI",
				function()
					ReloadUI()
				end,
				"The game writes Scry's data file only when the UI reloads or you log out. "
					.. "Reload now to hand the latest data to external apps.",
				true
			)
		)
		self.hasReloadButton = true
	end

	Settings.RegisterAddOnCategory(category)
	self.category = category
end

--- Open the settings page. Returns false (and says why) when it cannot be opened.
function Config:Open()
	if not self.category then
		print("Scry: the settings page is not available (see /scry status for errors).")
		return false
	end
	-- Opening the settings panel is a restricted action in combat.
	if InCombatLockdown() then
		print("Scry: settings cannot be opened in combat. Try again after the fight.")
		return false
	end
	Settings.OpenToCategory(self.category:GetID())
	return true
end

ns.SelfTest:Register("config: settings page is registered", function()
	assert(Config.category, "no settings category")
	local id = Config.category:GetID()
	assert(type(id) == "number", "category ID is " .. tostring(id))
	assert(Config.hasReloadButton, "CreateSettingsButtonInitializer is missing: no Reload UI button")
end)
