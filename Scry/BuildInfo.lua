-- Identifies which build of the addon is running. `./dev deploy` overwrites this
-- file in the deployed copy with a unique id and dev = true; `./dev wait` uses the
-- id to tell whether the game was running the code that was last deployed.
local _, ns = ...

ns.build = {
	id = "source",
	dev = false,
}
