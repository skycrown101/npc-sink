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

local function getStyleForRole(config, role)
	if config.RoleVisuals then
		return config.RoleVisuals[role]
	end
	return nil
end

local function getRoleColors(appearanceSeed, role, config)
	local rng = Random.new(appearanceSeed)
	local style = getStyleForRole(config, role)

	local bodyColor = Color3.fromHSV(rng:NextNumber(), 0.45, 0.85)
	local skinColor = Color3.fromHSV(rng:NextNumber(), 0.15, 0.95)
	local accentColor = Color3.fromHSV(rng:NextNumber(), 0.60, 0.70)

	if style then
		bodyColor = style.BodyColor or bodyColor
		skinColor = style.SkinColor or skinColor
		accentColor = style.AccentColor or accentColor
	end

	return bodyColor, skinColor, accentColor, style
end

local function makeNameLabel(config)
	local gui = Instance.new("BillboardGui")
	gui.Name = "TownLifeLabel"
	gui.Size = UDim2.fromOffset(config.NameLabelWidth or 140, config.NameLabelHeight or 34)
	gui.StudsOffset = Vector3.new(0, config.NameLabelStudsOffset or 3.2, 0)
	gui.AlwaysOnTop = config.NameLabelsAlwaysOnTop ~= false
	gui.LightInfluence = 0
	gui.Enabled = false

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamSemibold
	label.RichText = true
	label.TextScaled = true
	label.TextStrokeTransparency = 0.55
	label.TextWrapped = true
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.Parent = gui

	return gui
end

local function ensureNameLabel(model, head, config)
	local gui = model:FindFirstChild("TownLifeLabel")
	if gui and gui:IsA("BillboardGui") then
		gui.Adornee = head
		return gui
	end

	gui = makeNameLabel(config)
	gui.Adornee = head
	gui.Parent = model
	return gui
end

local function makeR6NPCModel(appearanceSeed, role, config)
	local bodyColor, skinColor, accentColor = getRoleColors(appearanceSeed, role, config)

	local model = Instance.new("Model")
	model.Name = "TownNPC_R6"

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

	ensureNameLabel(model, Head, config)

	model.PrimaryPart = Torso
	return model
end

local function buildLabelText(agent, config)
	local displayName = agent.displayName or ("NPC " .. tostring(agent.id))
	if config.ShowRoleLabels then
		return string.format("%s\n%s", displayName, agent.role or "Citizen")
	end
	return displayName
end

local function distSq(a, b)
	local dx = a.X - b.X
	local dy = a.Y - b.Y
	local dz = a.Z - b.Z
	return dx * dx + dy * dy + dz * dz
end

function Renderer.new(rootFolder, config)
	local self = {
		root = rootFolder,
		config = config,

		pool = {},
		active = {}, -- agentId -> model
		activeCount = 0,

		cache = {}, -- agentId -> {Torso=..., Head=..., LA=..., RA=..., LL=..., RL=..., Hat=..., Label=..., LabelText=...}
	}
	return setmetatable(self, { __index = Renderer })
end

local function buildCache(m)
	local label = m:FindFirstChild("TownLifeLabel")
	local text = nil
	if label and label:IsA("BillboardGui") then
		text = label:FindFirstChild("Text")
	end

	return {
		Torso = m:FindFirstChild("Torso"),
		Head = m:FindFirstChild("Head"),
		LA = m:FindFirstChild("Left Arm"),
		RA = m:FindFirstChild("Right Arm"),
		LL = m:FindFirstChild("Left Leg"),
		RL = m:FindFirstChild("Right Leg"),
		Hat = m:FindFirstChild("Hat"),
		Label = label,
		LabelText = text,
	}
end

function Renderer:applyAgentAppearance(m, agent)
	local parts = buildCache(m)
	local bodyColor, skinColor, accentColor, style = getRoleColors(agent.appearanceSeed, agent.role, self.config)

	if parts.Head then
		parts.Head.Color = skinColor
	end
	if parts.Torso then
		parts.Torso.Color = bodyColor
	end
	if parts.LA then
		parts.LA.Color = skinColor
	end
	if parts.RA then
		parts.RA.Color = skinColor
	end
	if parts.LL then
		parts.LL.Color = bodyColor
	end
	if parts.RL then
		parts.RL.Color = bodyColor
	end
	if parts.Hat then
		parts.Hat.Color = accentColor
		parts.Hat.Transparency = style and style.HatTransparency or 0
	end

	if parts.Head then
		parts.Label = ensureNameLabel(m, parts.Head, self.config)
		parts.LabelText = parts.Label and parts.Label:FindFirstChild("Text")
	end

	if parts.LabelText then
		parts.LabelText.TextColor3 = (style and style.LabelColor) or Color3.fromRGB(255, 255, 255)
	end

	-- cache label-related state once instead of rebuilding every frame
	agent._labelText = buildLabelText(agent, self.config)
	agent._labelEnabled = false
	agent._nextLabelCheckAt = 0

	if parts.Label then
		parts.Label.Enabled = false
	end
	if parts.LabelText then
		parts.LabelText.Text = agent._labelText
	end

	self.cache[agent.id] = parts
	return parts
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
		m = makeR6NPCModel(agent.appearanceSeed, agent.role, self.config)
	end

	m.Parent = self.root
	self.active[agent.id] = m
	self.activeCount += 1
	self:applyAgentAppearance(m, agent)

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
		parts = self:applyAgentAppearance(m, agent)
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

	if parts.Label then
		-- only re-check label visibility a few times per second
		if now >= (agent._nextLabelCheckAt or 0) then
			agent._nextLabelCheckAt = now + (self.config.NameLabelRefreshInterval or 0.25)

			local enabled = self.config.ShowNameLabels == true
			local cam = workspace.CurrentCamera
			local maxDistance = self.config.NameLabelMaxDistance or 90

			if enabled and cam then
				local maxDistanceSq = maxDistance * maxDistance
				enabled = distSq(cam.CFrame.Position, agent.pos) <= maxDistanceSq
			else
				enabled = false
			end

			agent._labelEnabled = enabled
			parts.Label.Enabled = enabled
		else
			parts.Label.Enabled = agent._labelEnabled == true
		end

		-- only rewrite text if it actually changed
		local labelText = agent._labelText or buildLabelText(agent, self.config)
		agent._labelText = labelText

		if parts.LabelText and parts.LabelText.Text ~= labelText then
			parts.LabelText.Text = labelText
		end
	end
end

return Renderer
