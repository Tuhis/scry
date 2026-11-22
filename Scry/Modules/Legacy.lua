-- Module "legacy": WoW: Forever's Legacy system. Legacy Points, the three Legacy
-- trees (trait trees) and completed Legacy Challenges (achievements underneath).
local _, ns = ...

local Legacy = ns:NewModule("legacy")

local function treeIDs()
	local consts = Constants.LegacyConsts
	return {
		consts.LEGACY_TREE_PROFESSIONS_ID,
		consts.LEGACY_TREE_ADVENTURE_ID,
		consts.LEGACY_TREE_PROGRESSION_ID,
	}
end

local function recordTrees()
	local consts = Constants.LegacyConsts
	local section = ns.DB:Section("legacy")
	local points = {
		earned = C_MajorFactions.GetCurrentRenownLevel(consts.LEGACY_REWARD_TRACK_FACTION_ID) or 0,
		max = C_Traits.GetMaxAvailableTraitCurrency(consts.LEGACY_POINTS_TRAIT_CURRENCY_ID, false) or 0,
	}
	local trees = {}
	for _, treeID in ipairs(treeIDs()) do
		local configID = C_Traits.GetConfigIDByTreeID(treeID)
		if configID then
			trees[treeID] = ns.TraitNodes(configID, treeID)
			-- All three trees spend the same currency; any of them reports it.
			local currencies = C_Traits.GetTreeCurrencyInfo(configID, treeID, false)
			local currency = currencies and currencies[1]
			if currency then
				points.unspent = currency.quantity
				points.spent = currency.spent
			end
		else
			ns.Log:Debug("legacy: no trait config for tree " .. treeID)
		end
	end
	section.points = points
	section.trees = trees
	ns.DB:Touch(section)
end

local function recordChallenges()
	local pointsCurrency = Constants.LegacyConsts.LEGACY_POINTS_TRAIT_CURRENCY_ID
	local section = ns.DB:Section("legacy")
	local challenges, count = {}, 0
	local categories = GetCategoryList() or {}
	for _, categoryID in ipairs(categories) do
		local numAchievements = GetCategoryNumAchievements(categoryID) or 0
		for index = 1, numAchievements do
			local id, name, _, completed, month, day, year, _, _, _, _, _, earnedByMe =
				GetAchievementInfo(categoryID, index)
			if id and completed then
				ns.DB:Name("achievements", id, name)
				local challenge = {
					earnedByMe = earnedByMe and true or false,
					points = C_Traits.GetTraitCurrencyForAchievement(pointsCurrency, id) or 0,
				}
				if month and day and year then
					-- The client reports the year as years since 2000.
					challenge.date = ("%04d-%02d-%02d"):format(year < 100 and 2000 + year or year, month, day)
				end
				challenges[id] = challenge
				count = count + 1
			end
		end
	end
	section.challenges = challenges
	ns.DB:Touch(section)
	ns.Log:Debug(("legacy: %d completed challenge(s) in %d categories"):format(count, #categories))
end

function Legacy:OnLogin()
	recordTrees()
	-- Walks every achievement category: keep it out of the login frame.
	ns:Debounce("legacy.challenges", 5, recordChallenges)
end

for _, event in ipairs({
	"TRAIT_CONFIG_UPDATED",
	"TRAIT_CONFIG_LIST_UPDATED",
	"TRAIT_TREE_CURRENCY_INFO_UPDATED",
	"MAJOR_FACTION_RENOWN_LEVEL_CHANGED",
}) do
	ns:On(event, function()
		ns:Debounce("legacy.trees", 1, recordTrees)
	end)
end
ns:On("ACHIEVEMENT_EARNED", function()
	ns:Debounce("legacy.challenges", 2, recordChallenges)
end)

ns.SelfTest:Register("legacy: all three trees are readable", function()
	local s = ns.DB:Section("legacy")
	for _, treeID in ipairs(treeIDs()) do
		assert(s.trees[treeID], "no trait config for legacy tree " .. treeID)
	end
	assert(s.points.unspent, "legacy point currency not readable")
end)
