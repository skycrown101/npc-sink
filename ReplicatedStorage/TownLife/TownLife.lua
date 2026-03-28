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

-- perf helpers
local function distSq(a, b)
	local dx = a.X - b.X
	local dy = a.Y - b.Y
	local dz = a.Z - b.Z
	return dx * dx + dy * dy + dz * dz
end

-- keeps list sorted by d2 asc, max size K
local function topKInsert(list, item, d2, K)
	local n = #list
	if n < K then
		list[n + 1] = { item = item, d2 = d2 }
	else
		-- if not better than worst then skip
		if d2 >= list[n].d2 then
			return
		end
		list[n] = { item = item, d2 = d2 }
	end

	-- bubble up last element to keep sorted
	local i = math.min(#list, K)
	while i > 1 and list[i].d2 < list[i - 1].d2 do
		list[i], list[i - 1] = list[i - 1], list[i]
		i -= 1
	end
end

-- world helpers
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
	local bestI, bestD2 = 1, math.huge
	for i, n in ipairs(graph.nodes) do
		local d2 = distSq(n.pos, pos)
		if d2 < bestD2 then
			bestD2, bestI = d2, i
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

	-- Patrol nodes are RoadNodes with Attribute Patrol = true
	local patrolNodes = {}
	for i, node in ipairs(graph.nodes) do
		if node.inst and node.inst:GetAttribute("Patrol") == true then
			table.insert(patrolNodes, i)
		end
	end

	-- Guard posts are hotspots with Type = "GuardPost"
	local guardPosts = {}
	for i, hs in ipairs(hotspots) do
		if hs.type == "GuardPost" then
			table.insert(guardPosts, i)
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
		rng = Random.new(math.random(1, 2 ^ 30)),

		-- perf runtime
		_visibleIds = {},
		_visibleList = {},

		patrolNodes = patrolNodes,
		guardPosts = guardPosts,
	}
end

-- public api
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

	-- spawn agent data
	local nextAgentId = 1
	local nowSpawn = os.clock()
	local allAgents = {} -- { { town = town, agent = agent }, ... }

	for _, town in ipairs(towns) do
		town._agentById = {}

		for _ = 1, town.popCap do
			-- create agent
			local agent = AgentSim.newAgent(nextAgentId, town.id, 1, Vector3.zero, town.rng)
			if AgentSim.assignRole then
				AgentSim.assignRole(agent, town, Config, town.rng)
			end
			
			if AgentSim.assignAnchors then
				AgentSim.assignAnchors(agent, town, Config, town.rng)
			end
			
			AgentSim.assignRole(agent, town, Config, town.rng)

			-- spawn gates
			if Config.SpawnGatesEnabled and AgentSim.initAtGate and town.spawnGates and #town.spawnGates > 0 then
				AgentSim.initAtGate(agent, town, Config, town.rng, nowSpawn)
			else
				local startNode = town.rng:NextInteger(1, #town.graph.nodes)
				local startPos = town.graph.nodes[startNode].pos
				agent.nodeIndex = startNode
				agent.pos = startPos
				agent.targetPos = nil
			end

			AgentSim.ensureTarget(agent, town, Config, town.rng, nowSpawn)

			table.insert(town.agents, agent)
			town._agentById[agent.id] = agent
			table.insert(allAgents, {
				town = town,
				agent = agent,
			})

			nextAgentId += 1
		end

		town._visibleIds = {}
		town._visibleList = {}
	end

	-- Disconnect any previous loop
	if TownLife._conn then
		TownLife._conn:Disconnect()
		TownLife._conn = nil
	end

	local accumNear, accumFar = 0, 0
	local nearTick = 1 / Config.SimHzNear
	local farTick = 1 / Config.SimHzFar

	local visTimer = 1e9
	local farRR = 0

	TownLife._conn = RunService.RenderStepped:Connect(function(dt)
		if not TownLife._running then
			return
		end

		accumNear += dt
		accumFar += dt
		visTimer += dt

		local now = os.clock()
		local doNear = accumNear >= nearTick
		local doFar = accumFar >= farTick
		local refreshEvery = Config.VisibilityRefreshInterval or 0.25
		local doVisibilityRefresh = visTimer >= refreshEvery

		if doNear then
			accumNear -= nearTick
		end
		if doFar then
			accumFar -= farTick
		end
		if doVisibilityRefresh then
			visTimer = 0
		end

		local focusPos = getFocusPos()
		local visR2 = Config.VisibleDistance * Config.VisibleDistance

		-- update town events first
		if doNear then
			for _, town in ipairs(towns) do
				EventSim.updateTown(town, Config, now, focusPos)
			end
		end

		-- global visibility refresh:
		-- choose ONE top-K across all towns, not K per town
		if doVisibilityRefresh then
			local globalTop = {}
			local K = Config.MaxVisibleNPCs or 20

			for _, town in ipairs(towns) do
				for _, agent in ipairs(town.agents) do
					if agent.state ~= "Despawned" then
						local d2 = distSq(agent.pos, focusPos)
						agent._d2 = d2

						if d2 <= visR2 then
							topKInsert(globalTop, {
								town = town,
								agent = agent,
							}, d2, K)
						end
					else
						agent._d2 = math.huge
					end
				end
			end

			local nextVisibleByTown = {}
			for _, town in ipairs(towns) do
				nextVisibleByTown[town] = {
					ids = {},
					list = {},
				}
			end

			for i = 1, #globalTop do
				local payload = globalTop[i].item
				local town = payload.town
				local agent = payload.agent
				local bucket = nextVisibleByTown[town]

				bucket.ids[agent.id] = true
				bucket.list[#bucket.list + 1] = {
					agent = agent,
					d2 = globalTop[i].d2,
				}
			end

			for _, town in ipairs(towns) do
				local bucket = nextVisibleByTown[town]
				local newVisibleIds = bucket.ids
				local newVisibleList = bucket.list
				local oldVisibleIds = town._visibleIds or {}

				-- release only agents that were visible in this town before,
				-- but are no longer visible now
				for agentId in pairs(oldVisibleIds) do
					if not newVisibleIds[agentId] then
						renderer:releaseAgent(agentId)
					end
				end

				town._visibleIds = newVisibleIds
				town._visibleList = newVisibleList

				-- ensure models exist only for newly visible/global-top agents
				for i = 1, #newVisibleList do
					renderer:getModelForAgent(newVisibleList[i].agent)
				end
			end
		else
			-- no full refresh: only update d2 for currently visible agents
			for _, town in ipairs(towns) do
				if town._visibleList then
					for i = 1, #town._visibleList do
						local agent = town._visibleList[i].agent
						agent._d2 = distSq(agent.pos, focusPos)
						town._visibleList[i].d2 = agent._d2
					end
				end
			end
		end

		-- dialogue, near sim, and visuals
		for _, town in ipairs(towns) do
			-- contextual dialogue
			if doNear then
				Dialogue.StepTown(town, Config, renderer, now)
			end

			-- near sim for only visible agents
			if doNear and town._visibleList then
				for i = 1, #town._visibleList do
					local agent = town._visibleList[i].agent
					if (agent._d2 or math.huge) <= visR2 and agent.state ~= "Despawned" then
						AgentSim.stepAgent(agent, town, Config, town.rng, nearTick, now, true)
					end
				end
			end

			-- visual update
			if town._visibleList then
				for i = 1, #town._visibleList do
					local agent = town._visibleList[i].agent
					if agent.state ~= "Despawned" then
						renderer:updateAgentVisual(agent, dt, now)
					else
						renderer:releaseAgent(agent.id)
					end
				end
			end
		end

		-- global far-sim budget:
		-- consume the budget once total, not once per town
		if doFar then
			local budget = Config.FarSimBudgetPerTick or 40
			local n = #allAgents

			if n > 0 then
				for _ = 1, budget do
					farRR = (farRR % n) + 1
					local entry = allAgents[farRR]
					local town = entry.town
					local agent = entry.agent

					if agent.state ~= "Despawned" and not (town._visibleIds and town._visibleIds[agent.id]) then
						AgentSim.stepAgent(agent, town, Config, town.rng, farTick, now, false)
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
