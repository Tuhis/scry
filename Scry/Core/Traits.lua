-- Shared reader for trait trees (class talents and the Legacy trees use the same system).
local _, ns = ...

--- nodeID -> active rank, for every node of `treeID` that has at least one rank.
--- Also records the nodes' names in ScryDB.names.traitNodes.
function ns.TraitNodes(configID, treeID)
	local nodes = {}
	for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID) or {}) do
		local node = C_Traits.GetNodeInfo(configID, nodeID)
		if node and node.activeRank and node.activeRank > 0 then
			nodes[nodeID] = node.activeRank
			local entryID = node.activeEntry and node.activeEntry.entryID or (node.entryIDs and node.entryIDs[1])
			local entry = entryID and C_Traits.GetEntryInfo(configID, entryID)
			local definition = entry and entry.definitionID and C_Traits.GetDefinitionInfo(entry.definitionID)
			if definition then
				local name = definition.overrideName
				if (not name or name == "") and definition.spellID then
					name = C_Spell.GetSpellName(definition.spellID)
				end
				ns.DB:Name("traitNodes", nodeID, name)
			end
		end
	end
	return nodes
end
