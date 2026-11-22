-- Module "skills": every skill line with its rank (professions, weapon skills, ...).
local _, ns = ...

local Skills = ns:NewModule("skills")

local function record()
	local section = ns.DB:Section("skills")
	local lines = {}
	for index = 1, C_SkillInfo.GetNumSkillLines() do
		local info = C_SkillInfo.GetSkillLineInfo(index)
		if info and not info.isHeader and info.skillID then
			lines[info.skillID] = { rank = info.rank, maxRank = info.maxRank }
		end
	end
	section.lines = lines
	ns.DB:Touch(section)
end

function Skills:OnLogin()
	record()
end

ns:On("SKILL_LINES_CHANGED", record)

ns.SelfTest:Register("skills: at least one skill line is listed", function()
	local s = ns.DB:Section("skills")
	assert(next(s.lines) ~= nil, "no skill lines (collapsed headers hide them?)")
end)
