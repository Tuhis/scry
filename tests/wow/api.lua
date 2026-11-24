-- Stubs for the WoW API, backed by wow.state. ADD NEW STUBS HERE.
--
-- Before stubbing anything, look up the real signature and return values:
--   ./dev api <name>            (signatures from Blizzard's API docs)
--   ./dev api --source <name>   (how Blizzard's own UI code uses it)
-- A stub must return what the real client returns (same order, same types,
-- including nil cases). A wrong stub makes tests pass on behaviour the game does
-- not have. Where behaviour is uncertain, also add an in-game selftest
-- (ns.SelfTest:Register) so `./dev report` verifies it against the real client.
--
-- To let tests control what a stub returns, read from wow.state and document the
-- field in default_state() in tests/wow/init.lua.

return function(wow, env)
	local state = wow.state

	-- Lua extensions and aliases the client provides ------------------------------
	env.xpcall = function(fn, handler, ...) -- WoW's xpcall forwards extra arguments
		local args, n = { ... }, select("#", ...)
		return xpcall(function()
			return fn(unpack(args, 1, n))
		end, handler)
	end
	env.print = function(...)
		local parts = {}
		for i = 1, select("#", ...) do
			parts[i] = tostring((select(i, ...)))
		end
		wow.printed[#wow.printed + 1] = table.concat(parts, " ")
	end
	env.format = string.format
	env.strfind, env.strmatch, env.strsub, env.strlen = string.find, string.match, string.sub, string.len
	env.strlower, env.strupper, env.strrep, env.gsub = string.lower, string.upper, string.rep, string.gsub
	env.strtrim = function(s)
		return (s:gsub("^%s+", ""):gsub("%s+$", ""))
	end
	env.strsplit = function(delimiter, s, pieces)
		local out, start = {}, 1
		while true do
			local i = (not pieces or #out < pieces - 1) and s:find(delimiter, start, true)
			if not i then
				out[#out + 1] = s:sub(start)
				break
			end
			out[#out + 1] = s:sub(start, i - 1)
			start = i + #delimiter
		end
		return unpack(out)
	end
	env.strjoin = function(delimiter, ...)
		return table.concat({ ... }, delimiter)
	end
	env.tinsert, env.tremove, env.sort = table.insert, table.remove, table.sort
	env.wipe = function(t)
		for k in pairs(t) do
			t[k] = nil
		end
		return t
	end
	env.tContains = function(t, value)
		for _, v in pairs(t) do
			if v == value then
				return true
			end
		end
		return false
	end
	env.floor, env.ceil, env.min, env.max, env.abs = math.floor, math.ceil, math.min, math.max, math.abs
	env.date = os.date
	env.time = function()
		return state.time
	end
	env.debugstack = function()
		return debug.traceback("", 2)
	end
	env.geterrorhandler = function()
		return wow.errorHandler
	end
	env.seterrorhandler = function(handler)
		wow.errorHandler = handler
	end

	-- Client / session ---------------------------------------------------------
	env.GetTime = function()
		return state.uptime
	end
	env.GetServerTime = function()
		return math.floor(state.time) -- whole seconds, as in game
	end
	env.GetLocale = function()
		return state.locale
	end
	env.GetBuildInfo = function()
		local b = state.build
		return b.version, b.number, b.date, b.interface, b.version, ""
	end
	env.ReloadUI = function()
		wow.reloadRequested = true -- tests call wow:reload() to actually perform it
	end
	env.Screenshot = function()
		wow.screenshots = wow.screenshots + 1
	end
	env.SlashCmdList = {}
	env.CreateFrame = function(frameType, name)
		return wow:_createFrame(frameType, name)
	end
	env.C_Timer = wow:namespace("C_Timer", {
		After = function(seconds, fn)
			wow.timers[#wow.timers + 1] = { at = state.uptime + seconds, fn = fn }
		end,
	})
	env.C_AddOns = wow:namespace("C_AddOns", {
		GetAddOnMetadata = function(name, field)
			if name == wow.addonName and wow.toc then
				return wow.toc.meta[field]
			end
			return nil
		end,
	})

	-- Realm --------------------------------------------------------------------
	env.GetRealmName = function()
		return state.realm.name
	end
	env.GetNormalizedRealmName = function()
		return state.realm.normalized
	end

	-- Units (only "player" is modelled so far) -----------------------------------
	local function player(unit)
		return unit == "player" and state.player or nil
	end
	env.UnitName = function(unit)
		local p = player(unit)
		return p and p.name, nil
	end
	env.UnitGUID = function(unit)
		local p = player(unit)
		return p and p.guid
	end
	env.UnitClass = function(unit)
		local p = player(unit)
		if p then
			return p.class.name, p.class.token, p.class.id
		end
	end
	env.UnitRace = function(unit)
		local p = player(unit)
		if p then
			return p.race.name, p.race.token, p.race.id
		end
	end
	env.UnitFactionGroup = function(unit)
		local p = player(unit)
		if p then
			return p.faction, p.faction
		end
	end
	env.UnitLevel = function(unit)
		local p = player(unit)
		return p and p.level or 0
	end
	env.UnitSexBase = function(unit)
		local p = player(unit)
		return p and p.sex
	end
	env.UnitXP = function(unit)
		local p = player(unit)
		return p and p.xp or 0
	end
	env.UnitXPMax = function(unit)
		local p = player(unit)
		return p and p.xpMax or 0
	end
	env.GetXPExhaustion = function()
		return state.player.restedXp or nil -- nil when not rested
	end
	env.GetBindLocation = function()
		return state.player.bindLocation
	end
	env.GetGuildInfo = function(unit) -- nothing when not in a guild
		local g = player(unit) and state.player.guild
		if g then
			return g.name, g.rankName, g.rankIndex
		end
	end
	env.GetMoney = function()
		return state.money
	end
	env.GetPVPLifetimeStats = function()
		return state.pvp.honorableKills, state.pvp.highestRank
	end
	env.GetInventoryItemID = function(unit, slot)
		local item = player(unit) and state.equipment[slot]
		return item and item.id
	end
	env.GetInventoryItemLink = function(unit, slot)
		local item = player(unit) and state.equipment[slot]
		return item and item.link
	end

	-- Enums and constants (values copied from `./dev api '^enum +Enum\.<Name> '`) -------
	env.Enum = {
		UnitSex = { Male = 0, Female = 1, None = 2, Both = 3, Neutral = 4 },
		ForeverExperiencePreset = { Classic = 0, Enhanced = 1 },
		BagIndex = {
			Keyring = -1,
			Backpack = 0,
			Bag_1 = 1,
			Bag_2 = 2,
			Bag_3 = 3,
			Bag_4 = 4,
			ReagentBag = 5,
			CharacterBankTab_1 = 6,
		},
		BankType = { Character = 0, Guild = 1, Account = 2 },
		SpellBookSpellBank = { Player = 0, Pet = 1 },
		TradeskillRelativeDifficulty = { Optimal = 0, Medium = 1, Easy = 2, Trivial = 3 },
		SpellBookItemType = { None = 0, Spell = 1, FutureSpell = 2, PetAction = 3, Flyout = 4 },
	}
	env.Constants = {
		LegacyConsts = {
			LEGACY_REWARD_TRACK_FACTION_ID = 2802,
			LEGACY_POINTS_TRAIT_CURRENCY_ID = 4225,
			LEGACY_TREE_PROFESSIONS_ID = 1187,
			LEGACY_TREE_ADVENTURE_ID = 1188,
			LEGACY_TREE_PROGRESSION_ID = 1189,
		},
	}

	-- Game rules / map -------------------------------------------------------------
	env.C_GameRules = wow:namespace("C_GameRules", {
		IsHardcoreActive = function()
			return state.player.hardcore
		end,
		GetForeverExperiencePreset = function()
			return state.player.experiencePreset or nil
		end,
	})
	env.C_Map = wow:namespace("C_Map", {
		GetMapInfo = function(uiMapID) -- nothing for an unknown map
			local name = state.mapNames[uiMapID]
			if name then
				return { mapID = uiMapID, name = name, mapType = 3, parentMapID = 0, flags = 0 }
			end
		end,
		GetBestMapForUnit = function(unit)
			return player(unit) and state.player.zone or nil
		end,
	})

	-- Items and containers. state.bags[bagID] = { size, slots = { [slot] = { id, count } } };
	-- state.items[itemID] = { sellPrice, cached = false to simulate data not loaded yet }.
	-- UNCERTAIN: whether the real client returns bank tab contents while the bank is
	-- closed. The stub does; the addon must not rely on it either way.
	env.C_Container = wow:namespace("C_Container", {
		GetContainerNumSlots = function(bagID)
			local bag = state.bags[bagID]
			return bag and bag.size or 0
		end,
		GetContainerItemInfo = function(bagID, slot) -- nothing for an empty slot
			local bag = state.bags[bagID]
			local item = bag and bag.slots[slot]
			if item then
				return {
					itemID = item.id,
					stackCount = item.count,
					isLocked = false,
					hasNoValue = false,
					isBound = false,
				}
			end
		end,
	})
	env.C_Item = wow:namespace("C_Item", {
		GetItemInfo = function(itemID) -- nothing until the item data is cached
			local item = state.items[itemID]
			if item and item.cached ~= false then
				local name = item.name or ("Item " .. itemID)
				return name,
					"|Hitem:" .. itemID .. "|h[" .. name .. "]|h",
					1,
					1,
					0,
					"Misc",
					"Junk",
					20,
					"",
					134400,
					item.sellPrice,
					15,
					0,
					0,
					0,
					nil,
					false,
					""
			end
		end,
		RequestLoadItemDataByID = function(itemID)
			wow.itemRequests[#wow.itemRequests + 1] = itemID
		end,
	})
	env.C_Bank = wow:namespace("C_Bank", {
		FetchPurchasedBankTabIDs = function(bankType)
			return bankType == 0 and state.bank.tabs or {}
		end,
	})

	-- Skills and professions --------------------------------------------------------
	env.C_SkillInfo = wow:namespace("C_SkillInfo", {
		GetNumSkillLines = function()
			return #state.skills
		end,
		GetSkillLineInfo = function(index)
			local s = state.skills[index]
			if s then
				return {
					skillID = s.skillID,
					name = s.name,
					isHeader = s.isHeader or false,
					isCollapsed = false,
					rank = s.rank or 0,
					maxRank = s.maxRank or 0,
					tempPoints = 0,
					modifier = 0,
					parentSkillLineID = 0,
				}
			end
		end,
	})
	-- state.tradeskill: the profession window. ready = open and loaded;
	-- recipes[recipeID] = learned (bool); recipeProfession[recipeID] = professionID;
	-- recipeAbility[recipeID] = skillLineAbilityID; recipeDifficulty[recipeID] =
	-- Enum.TradeskillRelativeDifficulty (nilable in the client).
	local function recipeInfo(recipeID)
		local t = state.tradeskill
		local learned = t.recipes[recipeID]
		if learned ~= nil then
			return {
				recipeID = recipeID,
				learned = learned,
				name = "Recipe " .. recipeID,
				skillLineAbilityID = t.recipeAbility[recipeID],
				relativeDifficulty = t.recipeDifficulty[recipeID],
			}
		end
	end
	local function sortedKeys(t)
		local keys = {}
		for k in pairs(t) do
			keys[#keys + 1] = k
		end
		table.sort(keys)
		return keys
	end
	env.C_TradeSkillUI = wow:namespace("C_TradeSkillUI", {
		IsTradeSkillReady = function()
			return state.tradeskill.ready
		end,
		IsTradeSkillLinked = function()
			return state.tradeskill.linked
		end,
		IsTradeSkillGuild = function()
			return state.tradeskill.guild
		end,
		IsNPCCrafting = function()
			return state.tradeskill.npc
		end,
		GetBaseProfessionInfo = function()
			local t = state.tradeskill
			return {
				professionID = t.ready and t.professionID or 0,
				professionName = t.ready and t.name or "",
				skillLevel = 0,
				maxSkillLevel = 0,
			}
		end,
		GetAllRecipeIDs = function()
			return state.tradeskill.ready and sortedKeys(state.tradeskill.recipes) or {}
		end,
		GetRecipeInfo = function(recipeID)
			return recipeInfo(recipeID)
		end,
		GetRecipeInfoForSkillLineAbility = function(skillLineAbilityID)
			for recipeID, abilityID in pairs(state.tradeskill.recipeAbility) do
				if abilityID == skillLineAbilityID then
					return recipeInfo(recipeID)
				end
			end
		end,
		GetProfessionInfoByRecipeID = function(recipeID)
			return { professionID = state.tradeskill.recipeProfession[recipeID] or 0, professionName = "" }
		end,
	})

	-- Spellbook. state.spellbook.lines = { { name, items = { { spellID, name, subName,
	-- isPassive, itemType, isOffSpec } } } }; state.spellbook.pet = list of items or nil.
	local function bookItem(item)
		if item then
			return {
				actionID = item.spellID or 0,
				spellID = item.spellID,
				itemType = item.itemType or 1,
				name = item.name or "",
				subName = item.subName or "",
				iconID = 136243,
				isPassive = item.isPassive or false,
				isOffSpec = item.isOffSpec or false,
			}
		end
	end
	env.C_SpellBook = wow:namespace("C_SpellBook", {
		GetNumSpellBookSkillLines = function()
			return #state.spellbook.lines
		end,
		GetSpellBookSkillLineInfo = function(lineIndex)
			local offset = 0
			for i, line in ipairs(state.spellbook.lines) do
				if i == lineIndex then
					return {
						name = line.name,
						iconID = 136243,
						itemIndexOffset = offset,
						numSpellBookItems = #line.items,
						isGuild = false,
						shouldHide = false,
					}
				end
				offset = offset + #line.items
			end
		end,
		GetSpellBookItemInfo = function(slot, bank)
			if bank == 1 then
				return bookItem(state.spellbook.pet and state.spellbook.pet[slot])
			end
			for _, line in ipairs(state.spellbook.lines) do
				if slot <= #line.items then
					return bookItem(line.items[slot])
				end
				slot = slot - #line.items
			end
		end,
		HasPetSpells = function() -- nothing without a pet
			if state.spellbook.pet then
				return #state.spellbook.pet, "PET"
			end
		end,
	})
	env.C_Spell = wow:namespace("C_Spell", {
		GetSpellSubtext = function(spellID)
			return state.spellSubtext[spellID]
		end,
		GetSpellName = function(spellID) -- nothing for an unknown spell
			return state.spellNames[spellID]
		end,
	})

	-- Traits (class talents and Legacy trees). state.traits: treeConfigs[treeID] = configID,
	-- configs[configID] = TraitConfigInfo, trees[treeID][nodeID] = active rank,
	-- currency = TreeCurrencyInfo or nil, maxAvailable, activeClassConfig, importString.
	env.C_Traits = wow:namespace("C_Traits", {
		GetConfigIDByTreeID = function(treeID)
			return state.traits.treeConfigs[treeID]
		end,
		GetConfigInfo = function(configID)
			return state.traits.configs[configID]
		end,
		GetTreeNodes = function(treeID)
			return sortedKeys(state.traits.trees[treeID] or {})
		end,
		GetNodeInfo = function(_, nodeID)
			for _, nodes in pairs(state.traits.trees) do
				if nodes[nodeID] then
					return {
						ID = nodeID, -- simplification: a node's only entry and its definition share its ID
						entryIDs = { nodeID },
						activeEntry = nodes[nodeID] > 0 and { entryID = nodeID, rank = nodes[nodeID] } or nil,
						activeRank = nodes[nodeID],
						currentRank = nodes[nodeID],
						ranksPurchased = nodes[nodeID],
						maxRanks = 5,
					}
				end
			end
			return { ID = 0, activeRank = 0, currentRank = 0, ranksPurchased = 0, maxRanks = 0 }
		end,
		GetEntryInfo = function(_, entryID)
			return {
				definitionID = entryID,
				type = 2,
				maxRanks = 5,
				isAvailable = true,
				isDisplayError = false,
				conditionIDs = {},
			}
		end,
		GetDefinitionInfo = function(definitionID) -- state.traits.definitions[id] = { spellID or overrideName }
			return state.traits.definitions[definitionID] or {}
		end,
		GetTreeCurrencyInfo = function()
			return { state.traits.currency }
		end,
		GetMaxAvailableTraitCurrency = function()
			return state.traits.maxAvailable
		end,
		GetTraitCurrencyForAchievement = function(_, achievementID)
			return state.achievementPoints[achievementID] or 0
		end,
		GenerateImportString = function()
			return state.traits.importString
		end,
	})
	env.C_ClassTalents = wow:namespace("C_ClassTalents", {
		GetActiveConfigID = function()
			return state.traits.activeClassConfig
		end,
	})
	env.C_SpecializationInfo = wow:namespace("C_SpecializationInfo", {
		GetSpecialization = function()
			return state.spec.index
		end,
		GetSpecializationInfo = function(index)
			if index == state.spec.index then
				return state.spec.id, state.spec.name, "", 136243, "DAMAGER", "INTELLECT"
			end
		end,
	})
	env.C_MajorFactions = wow:namespace("C_MajorFactions", {
		GetCurrentRenownLevel = function(factionID)
			return state.renown[factionID] or 0
		end,
	})

	-- Achievements (Legacy Challenges). state.achievements = { { id = categoryID,
	-- list = { { id, completed, month, day, year, earnedByMe } } } }.
	local function category(categoryID)
		for _, c in ipairs(state.achievements) do
			if c.id == categoryID then
				return c
			end
		end
	end
	env.GetCategoryList = function()
		local ids = {}
		for i, c in ipairs(state.achievements) do
			ids[i] = c.id
		end
		return ids
	end
	env.GetCategoryNumAchievements = function(categoryID)
		local c = category(categoryID)
		local total, completed = 0, 0
		for _, a in ipairs(c and c.list or {}) do
			total = total + 1
			completed = completed + (a.completed and 1 or 0)
		end
		return total, completed, total - completed
	end
	env.GetAchievementInfo = function(categoryID, index)
		local c = category(categoryID)
		local a = c and c.list[index]
		if a then
			local done = a.completed or false
			return a.id,
				"Challenge " .. a.id,
				10,
				done,
				done and a.month or nil,
				done and a.day or nil,
				done and a.year or nil,
				"",
				0,
				136243,
				"",
				false,
				a.earnedByMe or false,
				nil,
				false
		end
	end

	-- Reputation, currencies, quests ---------------------------------------------------
	env.C_Reputation = wow:namespace("C_Reputation", {
		GetNumFactions = function()
			return #state.reputations
		end,
		GetFactionDataByIndex = function(index)
			local f = state.reputations[index]
			if f then
				return {
					factionID = f.factionID,
					name = f.name or "",
					reaction = f.reaction or 4,
					currentStanding = f.currentStanding or 0,
					currentReactionThreshold = 0,
					nextReactionThreshold = 3000,
					isHeader = f.isHeader or false,
					isHeaderWithRep = f.isHeaderWithRep or false,
					isCollapsed = false,
				}
			end
		end,
	})
	env.C_CurrencyInfo = wow:namespace("C_CurrencyInfo", {
		GetCurrencyListSize = function()
			return #state.currencies
		end,
		GetCurrencyListInfo = function(index)
			local c = state.currencies[index]
			if c then
				return {
					name = c.name or "",
					currencyID = c.currencyID or 0,
					isHeader = c.isHeader or false,
					quantity = c.quantity or 0,
					maxQuantity = 0,
				}
			end
		end,
	})
	env.C_QuestLog = wow:namespace("C_QuestLog", {
		GetTitleForQuestID = function(questID) -- nil until the quest data is loaded
			return state.questTitles[questID]
		end,
		RequestLoadQuestByID = function(questID)
			wow.questRequests[#wow.questRequests + 1] = questID
		end,
		GetAllCompletedQuestIDs = function()
			local ids = {}
			for i, id in ipairs(state.quests) do
				ids[i] = id
			end
			return ids
		end,
	})
end
