-- Shared reader for trait trees (class talents and the Legacy trees use the same system).
local _, ns = ...

--- nodeID -> active rank, for every node of `treeID` that has at least one rank.
function ns.TraitNodes(configID, treeID)
	local nodes = {}
	for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID) or {}) do
		local node = C_Traits.GetNodeInfo(configID, nodeID)
		if node and node.activeRank and node.activeRank > 0 then
			nodes[nodeID] = node.activeRank
		end
	end
	return nodes
end
