local Wow = require("tests.wow")

local function scryCategory(wow)
	for _, category in ipairs(wow.settingsUI.categories) do
		if category.name == "Scry" then
			return category
		end
	end
end

local function combatLogSetting(wow)
	return scryCategory(wow).settings.SCRY_COMBATLOGATLOGIN
end

describe("settings", function()
	it("default to turning on the combat log at login, and save that", function()
		local wow = Wow.new():login()
		wow:assertNoErrors()
		assert.is_true(wow.state.combatLog.enabled)
		assert.is_true(wow.env.ScrySettings.combatLogAtLogin)
		assert.matches("combat logging turned on", wow.printed[#wow.printed])
		assert.matches("ScrySettings", wow:logout())
	end)

	it("leave a running combat log alone and say nothing", function()
		local wow = Wow.new({ combatLog = { enabled = true } }):login()
		wow:assertNoErrors()
		assert.is_true(wow.state.combatLog.enabled)
		for _, line in ipairs(wow.printed) do
			assert.not_matches("combat logging", line)
		end
	end)

	it("do not turn on the combat log when the saved setting is off", function()
		local wow = Wow.new({ saved = "ScrySettings = { combatLogAtLogin = false }" }):login()
		wow:assertNoErrors()
		assert.is_false(wow.state.combatLog.enabled)
		assert.is_false(wow.env.ScrySettings.combatLogAtLogin)
	end)

	it("replace invalid saved values with defaults and drop unknown keys", function()
		local wow = Wow.new({ saved = 'ScrySettings = { combatLogAtLogin = "yes", gone = 1 }' }):login()
		wow:assertNoErrors()
		assert.is_true(wow.env.ScrySettings.combatLogAtLogin)
		assert.is_nil(wow.env.ScrySettings.gone)

		wow = Wow.new({ saved = 'ScrySettings = "garbage"' }):login()
		wow:assertNoErrors()
		assert.same({ combatLogAtLogin = true }, wow.env.ScrySettings)
	end)
end)

describe("settings page", function()
	it("is registered in Options > AddOns as Scry, with the combat log checkbox", function()
		local wow = Wow.new():login()
		local category = scryCategory(wow)
		assert.is_table(category)
		assert.equals(category, wow.settingsUI.registered[category.id])
		local kinds = {}
		for _, e in ipairs(category.elements) do
			kinds[#kinds + 1] = e.kind
		end
		assert.same({ "header", "checkbox", "header", "button" }, kinds)
		local setting = combatLogSetting(wow)
		assert.equals(setting, category.elements[2].data.setting)
		assert.is_true(setting.defaultValue)
		assert.is_true(setting:GetValue())
	end)

	it("unchecking the box stops the combat log being started at the next login", function()
		local wow = Wow.new():login()
		combatLogSetting(wow):SetValue(false)
		wow:assertNoErrors()
		assert.is_true(wow.state.combatLog.enabled) -- a running log is not stopped
		wow:reload()
		assert.is_false(combatLogSetting(wow):GetValue())
		-- Next session, after the game has ended the log (e.g. a new login):
		wow.state.combatLog.enabled = false
		wow:reload()
		wow:assertNoErrors()
		assert.is_false(wow.state.combatLog.enabled)
	end)

	it("checking the box turns the combat log on right away", function()
		local wow = Wow.new({ saved = "ScrySettings = { combatLogAtLogin = false }" }):login()
		assert.is_false(wow.state.combatLog.enabled)
		combatLogSetting(wow):SetValue(true)
		wow:assertNoErrors()
		assert.is_true(wow.state.combatLog.enabled)
		assert.is_true(wow.env.ScrySettings.combatLogAtLogin)
	end)

	it("its button reloads the UI", function()
		local wow = Wow.new():login()
		scryCategory(wow).elements[4].data.buttonClick()
		assert.is_true(wow.reloadRequested)
	end)
end)

describe("/scry", function()
	it("opens the settings page", function()
		local wow = Wow.new():login()
		wow:slash("/scry")
		wow:slash("/scry settings")
		wow:assertNoErrors()
		local id = scryCategory(wow).id
		assert.same({ id, id }, wow.settingsUI.opened)
	end)

	it("does not open the settings page in combat", function()
		local wow = Wow.new({ inCombat = true }):login()
		wow:slash("/scry")
		wow:assertNoErrors()
		assert.same({}, wow.settingsUI.opened)
		assert.matches("in combat", wow.printed[#wow.printed])
	end)

	it("help lists the commands", function()
		local wow = Wow.new():login()
		wow:slash("/scry help")
		assert.matches("/scry opens the settings", wow.printed[#wow.printed])
	end)
end)
