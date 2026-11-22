-- luacheck configuration. The WoW API std is generated inside the toolchain image
-- (tools/docker/gen_api.lua): any global or C_Namespace member that does not exist
-- in the game client is reported as an error. Run via ./dev check.
std = "lua51"
max_line_length = false
codes = true
ignore = { "212/self" }
exclude_files = { "tests/golden" }

local wow = dofile((os.getenv("WOW_API_DIR") or "/opt/wow-api") .. "/luacheck_std.lua")
stds.wow = wow

files["Scry"] = {
	std = "lua51+wow",
	-- Globals the addon itself defines. Keep this list minimal: SavedVariables
	-- declared in Scry.toc and slash command registrations.
	globals = { "ScryDB", "ScryDevDB", "SLASH_SCRY1", "SlashCmdList" },
}
files["tests"] = { std = "lua51+busted" }
