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
	if cam then return cam.CFrame.Position end
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
	-- returns townsById[townId] = { zoneParts={}, roadNodes={}, pois={} }
	local townsById = {}
	
	for _, hs in ipairs(CollectionService:GetTagged("Hotspot")) do
		local id = getTownId(hs)
		if typeof(id) == "string" and id ~= "" then
			townsById[id] = townsById[id] or { zoneParts = {}, roadNodes = {}, pois = {}, hotspots = {} }
			table.insert(townsById[id].hotspots, hs)
		end
	end

	for _, zone in ipairs(CollectionService:GetTagged("TownZone")) do
		local id = getTownId(zone)
		if typeof(id) == "string" and id ~= "" then
			townsById[id] = townsById[id] or { zoneParts = {}, roadNodes = {}, pois = {} }
			table.insert(townsById[id].zoneParts, zone)
		end
	end

	for _, node in ipairs(CollectionService:GetTagged("RoadNode")) do
		local id = getTownId(node)
		if typeof(id) == "string" and id ~= "" then
			townsById[id] = townsById[id] or { zoneParts = {}, roadNodes = {}, pois = {} }
			table.insert(townsById[id].roadNodes, node)
		end
	end

	for _, poi in ipairs(CollectionService:GetTagged("POI")) do
		local id = getTownId(poi)
		if typeof(id) == "string" and id ~= "" then
			townsById[id] = townsById[id] or { zoneParts = {}, roadNodes = {}, pois = {} }
			table.insert(townsById[id].pois, poi)
		end
	end

	for _, gate in ipairs(CollectionService:GetTagged("SpawnGate")) do
	local id = getTownId(gate)
	if typeof(id) == "string" and id ~= "" then
		townsById[id] = townsById[id] or { zoneParts = {}, roadNodes = {}, pois = {}, hotspots = {}, spawnGates = {} }
		table.insert(townsById[id].spawnGates, gate)
		end
	end

	return townsById
end

local function buildTown(townId, raw)
	if #raw.roadNodes < 2 then
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

	local gates = {}
	if raw.spawnGates then
		for _, inst in ipairs(raw.spawnGates) do
			local weight = inst:GetAttribute("Weight")
			if typeof(weight) ~= "number" or weight <= 0 then weight = 1 end
	
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

	local pois = {}
	for _, inst in ipairs(raw.pois) do
		table.insert(pois, {
			name = inst.Name,
			pos = inst.Position,
			type = inst:GetAttribute("Type") or "Generic",
			inst = inst,
		})
	end

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
	if raw.zoneParts[1] then
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
		popCap = popCap,

		agents = {},
		rng = Random.new(math.random(1, 2^30)),
		hotspots = hotspots,
		spawnGates = gates,
	}
end

function TownLife.Start()
	if TownLife._running then return end
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
		return
	end

	-- Spawn agent data (no visuals yet)
	local nextAgentId = 1
	
	for _, town in ipairs(towns) do
		town._agentById = {}
	
		for i = 1, town.popCap do
			local startNode = town.rng:NextInteger(1, #town.graph.nodes)
			local startPos = town.graph.nodes[startNode].pos
	
			local agent = AgentSim.newAgent(nextAgentId, town.id, startNode, startPos, town.rng)
			AgentSim.ensureTarget(agent, town, Config, town.rng, os.clock())
	
			table.insert(town.agents, agent)
			town._agentById[agent.id] = agent
	
			nextAgentId += 1
		end
	endend

	town._agentById = {}
		for _, agent in ipairs(town.agents) do
			town._agentById[agent.id] = agent
	end

	-- Disconnect any previous loop (important if Start/Stop used)
	if TownLife._conn then
		TownLife._conn:Disconnect()
		TownLife._conn = nil
	end
		
	local accumNear, accumFar = 0, 0
	local nearTick = 1 / Config.SimHzNear
	local farTick = 1 / Config.SimHzFar

	TownLife._conn = RunService.RenderStepped:Connect(function(dt)
		if not TownLife._running then return end
	
		accumNear += dt
		accumFar += dt
	
		local now = os.clock()
		local doNear = accumNear >= nearTick
		local doFar = accumFar >= farTick
		if doNear then accumNear -= nearTick end
		if doFar then accumFar -= farTick end
	
		local focusPos = getFocusPos()
	
		for _, town in ipairs(towns) do
			-- Update events (meetups) per town
			if doNear then
				EventSim.updateTown(town, Config, now, focusPos)
			end
	
			-- Pick visible agents (closest first)
			local candidates = {}
			for _, agent in ipairs(town.agents) do
				local d = (agent.pos - focusPos).Magnitude
				if d <= Config.VisibleDistance then
					table.insert(candidates, {agent = agent, d = d})
				end
			end
			table.sort(candidates, function(a, b) return a.d < b.d end)
	
			local shouldBeVisible = {}
			for i = 1, math.min(#candidates, Config.MaxVisibleNPCs) do
				shouldBeVisible[candidates[i].agent.id] = true
			end
	
			-- Acquire/release models
			for _, agent in ipairs(town.agents) do
				if shouldBeVisible[agent.id] then
					renderer:getModelForAgent(agent)
				else
					renderer:releaseAgent(agent.id)
				end
			end
	
			-- Contextual meetup dialogue (speaker + reactions)
			if doNear then
				Dialogue.StepTown(town, Config, renderer, now)
			end
	
			-- Sim step
			for _, agent in ipairs(town.agents) do
				local d = (agent.pos - focusPos).Magnitude
				local isNear = d <= Config.VisibleDistance
	
				if isNear then
					if doNear then
						AgentSim.stepAgent(agent, town, Config, town.rng, nearTick, now, true)
					end
					renderer:updateAgentVisual(agent, dt, now)
				else
					if doFar then
						AgentSim.stepAgent(agent, town, Config, town.rng, farTick, now, false)
					end
				end
			end
		end
	end)
end

function TownLife.Stop()
	TownLife._running = false
	-- visuals cleanup: nukes the root folder
	local root = workspace:FindFirstChild("__TownLife")
	if TownLife._conn then
		TownLife._conn:Disconnect()
		TownLife._conn = nil
	end
	if root then root:Destroy() end
end

return TownLife
