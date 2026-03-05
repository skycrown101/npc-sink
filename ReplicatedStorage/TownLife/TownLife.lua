local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local Config = require(script.Parent.Config)
local Graph = require(script.Parent.Graph)
local AgentSim = require(script.Parent.AgentSim)
local Renderer = require(script.Parent.Renderer)
local EventSim = require(script.Parent.EventSim)
local Dialogue = require(script.Parent.Dialogue)

local TownLife = {}

local function distSq(a, b)
	local dx = a.X - b.X
	local dy = a.Y - b.Y
	local dz = a.Z - b.Z
	return dx*dx + dy*dy + dz*dz
end

-- keeps list sorted by d2 asc, max size K
local function topKInsert(list, agent, d2, K)
	local n = #list
	if n < K then
		list[n+1] = {agent = agent, d2 = d2}
	else
		-- if not better than worst, skip
		if d2 >= list[n].d2 then return end
		list[n] = {agent = agent, d2 = d2}
	end

	-- bubble up last element to keep sorted (K is small, this is cheap)
	local i = math.min(#list, K)
	while i > 1 and list[i].d2 < list[i-1].d2 do
		list[i], list[i-1] = list[i-1], list[i]
		i -= 1
	end
end

local function getOrCreateRoot()
	local root = workspace:FindFirstChild("__TownLife")
	if not root then
		root = Instance.new("Folder")
		root.Name = "__TownLife"
		root.Parent = workspace
	end
	return root
end

local function getCameraPos()
	local cam = workspace.CurrentCamera
	if cam then
		return cam.CFrame.Position
	end
	return Vector3.zero
end

local function getFocusPos()
	local lp = Players.LocalPlayer
	if lp and lp.Character and lp.Character.PrimaryPart then
		return lp.Character.PrimaryPart.Position
	end
	return getCameraPos()
end

local function getTownId(inst)
	return inst:GetAttribute("TownId")
end

local function scanTowns()
	-- townsById[townId] = { zoneParts={}, roadNodes={}, pois={}, hotspots={}, spawnGates={} }
	local townsById = {}

	local function ensureTown(id)
		local t = townsById[id]
		if not t then
			t = {
				zoneParts = {},
				roadNodes = {},
				pois = {},
				hotspots = {},
				spawnGates = {},
			}
			townsById[id] = t
		end
		return t
	end

	for _, zone in ipairs(CollectionService:GetTagged("TownZone")) do
		local id = getTownId(zone)
		if typeof(id) == "string" and id ~= "" then
			table.insert(ensureTown(id).zoneParts, zone)
		end
	end

	for _, node in ipairs(CollectionService:GetTagged("RoadNode")) do
		local id = getTownId(node)
		if typeof(id) == "string" and id ~= "" then
			table.insert(ensureTown(id).roadNodes, node)
		end
	end

	for _, poi in ipairs(CollectionService:GetTagged("POI")) do
		local id = getTownId(poi)
		if typeof(id) == "string" and id ~= "" then
			table.insert(ensureTown(id).pois, poi)
		end
	end

	for _, hs in ipairs(CollectionService:GetTagged("Hotspot")) do
		local id = getTownId(hs)
		if typeof(id) == "string" and id ~= "" then
			table.insert(ensureTown(id).hotspots, hs)
		end
	end

	for _, gate in ipairs(CollectionService:GetTagged("SpawnGate")) do
		local id = getTownId(gate)
		if typeof(id) == "string" and id ~= "" then
			table.insert(ensureTown(id).spawnGates, gate)
		end
	end

	return townsById
end

local function findNearestNodeIndex(graph, pos)
	local bestI, bestD = 1, math.huge
	for i, n in ipairs(graph.nodes) do
		local d = (n.pos - pos).Magnitude
		if d < bestD then
			bestD, bestI = d, i
		end
	end
	return bestI
end

local function buildTown(townId, raw)
	if not raw or not raw.roadNodes or #raw.roadNodes < 2 then
		warn(("TownLife: Town '%s' has <2 RoadNodes; skipping."):format(townId))
		return nil
	end

	local nodes = {}
	for _, inst in ipairs(raw.roadNodes) do
		table.insert(nodes, {
			name = inst.Name,
			pos = inst.Position,
			inst = inst,
		})
	end

	local graph = Graph.build(nodes, Config)

	-- Spawn gates
	local gates = {}
	if raw.spawnGates then
		for _, inst in ipairs(raw.spawnGates) do
			local weight = inst:GetAttribute("Weight")
			if typeof(weight) ~= "number" or weight <= 0 then
				weight = 1
			end

			local nodeName = inst:GetAttribute("Node")
			local nodeIndex
			if typeof(nodeName) == "string" and nodeName ~= "" and graph.byName[nodeName] then
				nodeIndex = graph.byName[nodeName]
			else
				nodeIndex = findNearestNodeIndex(graph, inst.Position)
			end

			table.insert(gates, {
				name = inst.Name,
				pos = inst.Position,
				weight = weight,
				nodeIndex = nodeIndex,
				inst = inst,
			})
		end
	end

	-- POIs
	local pois = {}
	if raw.pois then
		for _, inst in ipairs(raw.pois) do
			table.insert(pois, {
				name = inst.Name,
				pos = inst.Position,
				type = inst:GetAttribute("Type") or "Generic",
				inst = inst,
			})
		end
	end

	-- Hotspots
	local hotspots = {}
	if raw.hotspots then
		for _, inst in ipairs(raw.hotspots) do
			table.insert(hotspots, {
				name = inst.Name,
				pos = inst.Position,
				type = inst:GetAttribute("Type") or "Generic",
				inst = inst,
			})
		end
	end

	local popCap = Config.MaxAgentsPerTownDefault
	if raw.zoneParts and raw.zoneParts[1] then
		local zcap = raw.zoneParts[1]:GetAttribute("PopulationCap")
		if typeof(zcap) == "number" then
			popCap = math.max(0, math.floor(zcap))
		end
	end

	return {
		id = townId,
		raw = raw,
		graph = graph,

		pois = pois,
		hotspots = hotspots,
		spawnGates = gates,

		popCap = popCap,
		agents = {},
		_agentById = {},
		rng = Random.new(math.random(1, 2^30)),
	}
end

function TownLife.Start()
	if TownLife._running then
		return
	end
	TownLife._running = true

	local root = getOrCreateRoot()
	local renderer = Renderer.new(root, Config)
	Dialogue.EnsureBubbleChat(Config)

	local townsById = scanTowns()
	local towns = {}

	for townId, raw in pairs(townsById) do
		local town = buildTown(townId, raw)
		if town then
			table.insert(towns, town)
		end
	end

	if #towns == 0 then
		warn("TownLife: No towns found. Add TownZone + RoadNode tags/attributes.")
		TownLife._running = false
		return
	end

	-- Spawn agent data
	local nextAgentId = 1
	local nowSpawn = os.clock()

	for _, town in ipairs(towns) do
		town._agentById = {}

		for i = 1, town.popCap do
			-- Create with dummy values; initAtGate (if present) will override
			local agent = AgentSim.newAgent(nextAgentId, town.id, 1, Vector3.zero, town.rng)

			-- If you implemented spawn gates in AgentSim, use them
			if Config.SpawnGatesEnabled and AgentSim.initAtGate and town.spawnGates and #town.spawnGates > 0 then
				AgentSim.initAtGate(agent, town, Config, town.rng, nowSpawn)
			else
				-- fallback: start at random road node
				local startNode = town.rng:NextInteger(1, #town.graph.nodes)
				local startPos = town.graph.nodes[startNode].pos
				agent.nodeIndex = startNode
				agent.pos = startPos
				agent.targetPos = nil
			end

			AgentSim.ensureTarget(agent, town, Config, town.rng, nowSpawn)

			table.insert(town.agents, agent)
			town._agentById[agent.id] = agent
			nextAgentId += 1
		end
	end

	-- Disconnect any previous loop
	if TownLife._conn then
		TownLife._conn:Disconnect()
		TownLife._conn = nil
	end

	local accumNear, accumFar = 0, 0
	local nearTick = 1 / Config.SimHzNear
	local farTick = 1 / Config.SimHzFar

	TownLife._conn = RunService.RenderStepped:Connect(function(dt)
		if not TownLife._running then
			return
		end

		accumNear += dt
		accumFar += dt

		local now = os.clock()
		local doNear = accumNear >= nearTick
		local doFar = accumFar >= farTick
		if doNear then accumNear -= nearTick end
		if doFar then accumFar -= farTick end

		local focusPos = getFocusPos()

		for _, town in ipairs(towns) do
			-- Meetups/events
			if doNear then
				EventSim.updateTown(town, Config, now, focusPos)
			end
		
			-- ---- VISIBILITY REFRESH (rate-limited) ----
			town._visTimer = (town._visTimer or 0) + dt
		
			local visR2 = Config.VisibleDistance * Config.VisibleDistance
			local refreshEvery = Config.VisibilityRefreshInterval or 0.25
		
			if town._visTimer >= refreshEvery or not town._visibleIds then
				town._visTimer = 0
		
				local K = Config.MaxVisibleNPCs
				local top = {}
		
				-- Scan agents once (distance²), keep only top K
				for _, agent in ipairs(town.agents) do
					if agent.state ~= "Despawned" then
						local d2 = distSq(agent.pos, focusPos)
						agent._d2 = d2 -- cache for sim decisions
						if d2 <= visR2 then
							topKInsert(top, agent, d2, K)
						end
					else
						agent._d2 = math.huge
					end
				end
		
				-- Build visible set for this town
				local visibleIds = {}
				for i = 1, #top do
					visibleIds[top[i].agent.id] = true
				end
				town._visibleIds = visibleIds
				town._visibleList = top
		
				-- Release models that belong to this town but are no longer visible
				for agentId in pairs(renderer.active) do
					if town._agentById[agentId] and not visibleIds[agentId] then
						renderer:releaseAgent(agentId)
					end
				end
		
				-- Ensure models for currently visible agents (no full-agent loop needed)
				for i = 1, #top do
					renderer:getModelForAgent(top[i].agent)
				end
			else
				-- Even when not refreshing, still cache d2 cheaply for the visible ones
				-- (so near/far decisions stay responsive without rescanning everyone)
				if town._visibleList then
					for i = 1, #town._visibleList do
						local agent = town._visibleList[i].agent
						agent._d2 = distSq(agent.pos, focusPos)
					end
				end
			end
		
			-- Contextual meetup dialogue (speaker + reactions)
			if doNear then
				Dialogue.StepTown(town, Config, renderer, now)
			end
		
			-- ---- NEAR SIM: only step visible agents (<= MaxVisibleNPCs) ----
			if doNear and town._visibleList then
				for i = 1, #town._visibleList do
					local agent = town._visibleList[i].agent
					-- Only step if still near-ish
					if (agent._d2 or math.huge) <= visR2 and agent.state ~= "Despawned" then
						AgentSim.stepAgent(agent, town, Config, town.rng, nearTick, now, true)
					end
				end
			end
		
			-- ---- VISUAL UPDATE: only visible agents each frame ----
			if town._visibleList then
				for i = 1, #town._visibleList do
					local agent = town._visibleList[i].agent
					if agent.state ~= "Despawned" then
						renderer:updateAgentVisual(agent, dt, now)
					else
						-- If agent despawned, hide immediately
						renderer:releaseAgent(agent.id)
					end
				end
			end
		
			-- ---- FAR SIM: budgeted round-robin (prevents spikes for huge towns) ----
			if doFar then
				local budget = Config.FarSimBudgetPerTick or 40
				local n = #town.agents
				if n > 0 then
					for _ = 1, budget do
						town._farRR = (town._farRR % n) + 1
						local agent = town.agents[town._farRR]
		
						-- Skip visible agents and despawned ones (despawned agent sim handled inside AgentSim if you do that)
						if agent.state ~= "Despawned" and not (town._visibleIds and town._visibleIds[agent.id]) then
							AgentSim.stepAgent(agent, town, Config, town.rng, farTick, now, false)
						end
					end
				end
			end
		end
	end)
end

function TownLife.Stop()
	TownLife._running = false

	if TownLife._conn then
		TownLife._conn:Disconnect()
		TownLife._conn = nil
	end

	local root = workspace:FindFirstChild("__TownLife")
	if root then
		root:Destroy()
	end
end

return TownLife
