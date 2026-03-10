local Renderer = {}

local function makePart(name, size, color)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Material = Enum.Material.SmoothPlastic
	p.Color = color
	return p
end

local function makeR6NPCModel(appearanceSeed)
	local rng = Random.new(appearanceSeed)

	local model = Instance.new("Model")
	model.Name = "TownNPC_R6"

	local bodyColor = Color3.fromHSV(rng:NextNumber(), 0.45, 0.85)
	local skinColor = Color3.fromHSV(rng:NextNumber(), 0.15, 0.95)
	local accentColor = Color3.fromHSV(rng:NextNumber(), 0.60, 0.70)

	local Head = makePart("Head", Vector3.new(2, 1, 1), skinColor)
	local Torso = makePart("Torso", Vector3.new(2, 2, 1), bodyColor)
	local LeftArm = makePart("Left Arm", Vector3.new(1, 2, 1), skinColor)
	local RightArm = makePart("Right Arm", Vector3.new(1, 2, 1), skinColor)
	local LeftLeg = makePart("Left Leg", Vector3.new(1, 2, 1), bodyColor)
	local RightLeg = makePart("Right Leg", Vector3.new(1, 2, 1), bodyColor)

	Head.Parent = model
	Torso.Parent = model
	LeftArm.Parent = model
	RightArm.Parent = model
	LeftLeg.Parent = model
	RightLeg.Parent = model

	local Hat = Instance.new("Part")
	Hat.Name = "Hat"
	Hat.Shape = Enum.PartType.Cylinder
	Hat.Size = Vector3.new(0.35, 2.0, 2.0)
	Hat.Anchored = true
	Hat.CanCollide = false
	Hat.CanQuery = false
	Hat.CanTouch = false
	Hat.Material = Enum.Material.SmoothPlastic
	Hat.Color = accentColor
	Hat.Parent = model

	model.PrimaryPart = Torso
	return model
end

function Renderer.new(rootFolder, config)
	local self = {
		root = rootFolder,
		config = config,

		pool = {},
		active = {}, -- agentId -> model
		activeCount = 0, -- faster than recounting

		cache = {}, -- agentId -> {Torso=..., Head=..., LA=..., RA=..., LL=..., RL=..., Hat=...}
	}
	return setmetatable(self, { __index = Renderer })
end

local function buildCache(m)
	return {
		Torso = m:FindFirstChild("Torso"),
		Head = m:FindFirstChild("Head"),
		LA = m:FindFirstChild("Left Arm"),
		RA = m:FindFirstChild("Right Arm"),
		LL = m:FindFirstChild("Left Leg"),
		RL = m:FindFirstChild("Right Leg"),
		Hat = m:FindFirstChild("Hat"),
	}
end

function Renderer:getModelForAgent(agent)
	local m = self.active[agent.id]
	if m then
		return m
	end

	if self.activeCount >= self.config.MaxVisibleNPCs then
		return nil
	end

	m = table.remove(self.pool)
	if not m then
		m = makeR6NPCModel(agent.appearanceSeed)
	end

	m.Parent = self.root
	self.active[agent.id] = m
	self.activeCount += 1
	self.cache[agent.id] = buildCache(m)

	return m
end

function Renderer:releaseAgent(agentId)
	local m = self.active[agentId]
	if not m then
		return
	end

	self.active[agentId] = nil
	self.cache[agentId] = nil
	self.activeCount -= 1

	m.Parent = nil
	table.insert(self.pool, m)
end

local OFFSETS = {
	Head = CFrame.new(0, 1.5, 0),
	LeftArm = CFrame.new(-1.5, 0, 0),
	RightArm = CFrame.new(1.5, 0, 0),
	LeftLeg = CFrame.new(-0.5, -2, 0),
	RightLeg = CFrame.new(0.5, -2, 0),
	Hat = CFrame.new(0, 2.25, 0) * CFrame.Angles(0, 0, math.rad(90)),
}

function Renderer:updateAgentVisual(agent, dt, now)
	local m = self.active[agent.id]
	if not m then
		return
	end

	local parts = self.cache[agent.id]
	if not parts or not parts.Torso then
		-- recover if cache got lost
		self.cache[agent.id] = buildCache(m)
		parts = self.cache[agent.id]
		if not parts or not parts.Torso then
			return
		end
	end

	local torso = parts.Torso

	local baseY = 2.0
	local torsoPos = agent.pos + Vector3.new(0, baseY, 0)

	local bob = 0
	if agent.state == "Walk" or agent.state == "MeetupGo" then
		bob = math.sin(now * 10 + (agent.appearanceSeed % 97)) * 0.06
	end

	local rootCF = CFrame.new(torsoPos + Vector3.new(0, bob, 0)) * CFrame.Angles(0, agent.yaw, 0)
	torso.CFrame = rootCF

	local swing = 0
	if agent.state == "Walk" or agent.state == "MeetupGo" then
		swing = math.sin(now * 8 + (agent.appearanceSeed % 53)) * 0.55
	end

	if parts.Head then
		parts.Head.CFrame = rootCF * OFFSETS.Head
	end
	if parts.LA then
		parts.LA.CFrame = rootCF * OFFSETS.LeftArm * CFrame.Angles(swing, 0, 0)
	end
	if parts.RA then
		parts.RA.CFrame = rootCF * OFFSETS.RightArm * CFrame.Angles(-swing, 0, 0)
	end
	if parts.LL then
		parts.LL.CFrame = rootCF * OFFSETS.LeftLeg * CFrame.Angles(-swing, 0, 0)
	end
	if parts.RL then
		parts.RL.CFrame = rootCF * OFFSETS.RightLeg * CFrame.Angles(swing, 0, 0)
	end

	-- hat follows head
	if parts.Hat and parts.Head then
		parts.Hat.CFrame = (rootCF * OFFSETS.Head) * OFFSETS.Hat
	end
end

return Renderer
