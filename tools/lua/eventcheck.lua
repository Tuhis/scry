-- Static check: every event name the addon subscribes to must be a real event.
-- (The test mock checks this too, but only on code paths the tests execute.)
-- usage: lua eventcheck.lua <file.lua>...
local api = dofile(os.getenv("WOW_API_DIR") .. "/api.lua")
local bad = 0
for _, path in ipairs(arg) do
	local n = 0
	for line in io.lines(path) do
		n = n + 1
		for call, event in line:gmatch('([%w_.:]+)%s*%(%s*"([A-Z][A-Z0-9_]+)"') do
			local name = call:match("[^.:]+$")
			if (name == "On" or name == "RegisterEvent" or name == "RegisterUnitEvent") and not api.events[event] then
				print(("%s:%d: unknown event %q (search: ./dev api %s)"):format(path, n, event, event:match("^[A-Z]+")))
				bad = bad + 1
			end
		end
	end
end
os.exit(bad == 0 and 0 or 1)
