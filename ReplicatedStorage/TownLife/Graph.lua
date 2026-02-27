local Graph = {}

local function parseCSV(str)
	local out = {}
	if not str or str == "" then return out end
	for token in string.gmatch(str, "([^,]+)") do
		token = token:gsub("^%s+", ""):gsub("%s+$", "")
		table.insert(out, token)
	end
	return out
end

function Graph.build(nodes, config)
	-- nodes: { {name=string, pos=Vector3, inst=Instance} ... }
	local byName = {}
	for i, n in ipairs(nodes) do
		byName[n.name] = i
	end

	local adj = table.create(#nodes)
	for i = 1, #nodes do adj[i] = {} end

	-- Manual links first
	for i, n in ipairs(nodes) do
		local links = n.inst:GetAttribute("Links")
		if links then
			for _, otherName in ipairs(parseCSV(links)) do
				local j = byName[otherName]
				if j then
					adj[i][j] = true
					adj[j][i] = true
				end
			end
		end
	end

	-- Auto-links (distance-based) if graph is sparse
	local autoDist = config.AutoLinkDistance
	for i = 1, #nodes do
		-- count existing
		local count = 0
		for _ in pairs(adj[i]) do count += 1 end
		if count >= 1 then
			continue
		end

		-- find nearest neighbors
		local scored = {}
		for j = 1, #nodes do
			if i ~= j then
				local d = (nodes[i].pos - nodes[j].pos).Magnitude
				if d <= autoDist then
					table.insert(scored, {j=j, d=d})
				end
			end
		end
		table.sort(scored, function(a,b) return a.d < b.d end)

		local maxLinks = math.min(config.MaxNeighborLinks, #scored)
		for k = 1, maxLinks do
			local j = scored[k].j
			adj[i][j] = true
			adj[j][i] = true
		end
	end

	-- Flatten adjacency sets into arrays for faster random choice
	local neighbors = table.create(#nodes)
	for i = 1, #nodes do
		local list = {}
		for j in pairs(adj[i]) do
			table.insert(list, j)
		end
		neighbors[i] = list
	end

	return {
		nodes = nodes,
		neighbors = neighbors,
		byName = byName,
	}
end

function Graph.randomNeighbor(graph, nodeIndex, rng)
	local list = graph.neighbors[nodeIndex]
	if not list or #list == 0 then
		return nil
	end
	return list[rng:NextInteger(1, #list)]
end

return Graph
