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
		for i = 1, town.popCap do
			local startNode = town.rng:NextInteger(1, #town.graph.nodes)
			local startPos = town.graph.nodes[startNode].pos
			local agent = AgentSim.newAgent(nextAgentId, town.id, startNode, startPos, town.rng)
			AgentSim.ensureTarget(agent, town, Config, town.rng, os.clock())
			table.insert(town.agents, agent)
			nextAgentId += 1
		end
	end

	town._agentById = {}
		for _, agent in ipairs(town.agents) do
			town._agentById[agent.id] = agent
	end

	-- Main loop with budgets
	local accum = 0
	local nearTick = 1 / Config.SimHzNear
	local farTick = 1 / Config.SimHzFar

	RunService.RenderStepped:Connect(function(dt)
		if not TownLife._running then return end
		accum += dt
		local now = os.clock()

		-- Decide which tick to run (cheap): we can run near steps frequently, far less frequently
		local doNear = accum >= nearTick
		local doFar = accum >= farTick

		if doNear then
			-- keep accum from growing without bound
			accum = 0
		end

		local focusPos = getFocusPos()
		EventSim.updateTown(town, Config, now, focusPos)

		-- Render selection + sim
		for _, town in ipairs(towns) do
			-- Pick a candidate list of agents near enough to render
			local candidates = {}
			for _, agent in ipairs(town.agents) do
				local d = (agent.pos - focusPos).Magnitude
				if d <= Config.VisibleDistance then
					table.insert(candidates, {agent=agent, d=d})
				end
			end
			table.sort(candidates, function(a,b) return a.d < b.d end)

			-- Mark who should be visible (up to cap, global cap enforced by renderer)
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

			-- Step sim: near agents frequently, far agents occasionally
			for _, agent in ipairs(town.agents) do
				local d = (agent.pos - focusPos).Magnitude
				local isNear = d <= Config.VisibleDistance

				if isNear then
					if doNear then
						AgentSim.stepAgent(agent, town, Config, town.rng, nearTick, now, true)
					end
					renderer:updateAgentVisual(agent, dt, now)
					local model = renderer.active[agent.id]
					Dialogue.MaybeSpeak(Config, town.rng, agent, model, now)
				else
					-- data-only far sim at low rate
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
	if root then root:Destroy() end
end

return TownLife
