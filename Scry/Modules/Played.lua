-- Module "played": time played. The client only reports it in answer to /played
-- (asking for it ourselves would print the answer into the chat on every login),
-- so this is recorded whenever the player types /played.
local _, ns = ...

ns:NewModule("played")

ns:On("TIME_PLAYED_MSG", function(total, thisLevel)
	local section = ns.DB:Section("played")
	section.total = total
	section.thisLevel = thisLevel
	ns.DB:Touch(section)
end)
