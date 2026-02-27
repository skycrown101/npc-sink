local Renderer = {}

local function makeNPCModel(appearanceSeed)
	-- Cheap non-humanoid “person”: 2 parts + optional “hat” nub
	local rng = Random.new(appearanceSeed)

	local model = Instance.new("Model")
	model.Name = "TownNPC"

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(1.2, 2.2, 0.9)
	body.Anchored = true
	body.CanCollide = false
	body.CanQuery = false
	body.CanTouch = false
	body.Material = Enum.Material.SmoothPlastic
	body.Color = Color3.fromHSV(rng:NextNumber(), 0.55, 0.85)
	body.Parent = model

	local head = Instance.new("Part")
	head.Name = "Head"
	head.Shape = Enum.PartType.Ball
	head.Size = Vector3.new(1.1, 1.1, 1.1)
	head.Anchored = true
	head.CanCollide = false
	head.CanQuery = false
	head.CanTouch = false
	head.Material = Enum.Material.SmoothPlastic
	head.Color = Color3.fromHSV(rng:NextNumber(), 0.25, 0.95)
	head.Parent = model

	local hat = Instance.new("Part")
	hat.Name = "Hat"
	hat.Shape = Enum.PartType.Cylinder
	hat.Size = Vector3.new(0.35, 1.1, 1.1)
	hat.Anchored = true
	hat.CanCollide = false
	hat.CanQuery = false
	hat.CanTouch = false
	hat.Material = Enum.Material.SmoothPlastic
	hat.Color = Color3.fromHSV(rng:NextNumber(), 0.65, 0.6)
	hat.Parent = model

	model.PrimaryPart = body
	return model
end

function Renderer.new(rootFolder, config)
	local self = {
		root = rootFolder,
		config = config,
		pool = {},       -- unused models
		active = {},     -- agentId -> model
	}

	return setmetatable(self, {__index = Renderer})
end

function Renderer:getModelForAgent(agent)
	local m = self.active[agent.id]
	if m then return m end

	-- cap visible
	local activeCount = 0
	for _ in pairs(self.active) do activeCount += 1 end
	if activeCount >= self.config.MaxVisibleNPCs then
		return nil
	end

	-- reuse or create
	m = table.remove(self.pool)
	if not m then
		m = makeNPCModel(agent.appearanceSeed)
	end
	m.Parent = self.root
	self.active[agent.id] = m
	return m
end

function Renderer:releaseAgent(agentId)
	local m = self.active[agentId]
	if not m then return end
	self.active[agentId] = nil
	m.Parent = nil
	table.insert(self.pool, m)
end

function Renderer:updateAgentVisual(agent, dt, now)
	local m = self.active[agent.id]
	if not m then return end

	-- Fake walk bob
	local bob = 0
	if agent.state == "Walk" then
		bob = math.sin(now * 10 + agent.appearanceSeed % 100) * 0.06
	end

	local pos = agent.pos + Vector3.new(0, 1.1 + bob, 0)
	local cf = CFrame.new(pos) * CFrame.Angles(0, agent.yaw, 0)

	local body = m.PrimaryPart
	body.CFrame = cf

	local head = m:FindFirstChild("Head")
	if head then head.CFrame = cf * CFrame.new(0, 1.35, 0) end

	local hat = m:FindFirstChild("Hat")
	if hat then hat.CFrame = cf * CFrame.new(0, 2.1, 0) * CFrame.Angles(0, 0, math.rad(90)) end
end

return Renderer
