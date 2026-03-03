local AgentSim = {}

local function randRange(rng, a, b)
	return a + (b - a) * rng:NextNumber()
end

local function randRange(rng, a, b)
	return a + (b - a) * rng:NextNumber()
end

local function weightedPickGateIndex(gates, rng)
	if not gates or #gates == 0 then return nil end
	local total = 0
	for _, g in ipairs(gates) do total += (g.weight or 1) end
	local r = rng:NextNumber() * total
	local acc = 0
	for i, g in ipairs(gates) do
		acc += (g.weight or 1)
		if r <= acc then return i end
	end
	return 1
end

function AgentSim.newAgent(id, townId, startNodeIndex, startPos, rng)
	return {
		id = id,
		townId = townId,

		-- simulation state
		state = "Walk", -- Walk | Idle
		nodeIndex = startNodeIndex,

		pos = startPos,
		yaw = rng:NextNumber() * math.pi * 2,

		targetType = "Node", -- Node | POI
		targetIndex = nil,   -- node index (if Node) OR poi index (if POI)
		targetPos = startPos,

		idleUntil = 0,

		-- visuals
		appearanceSeed = rng:NextInteger(1, 2^30),
		nextTalkAt = 0,
		
		homeGateIndex = nil,
		leavingAt = 0,
		respawnAt = 0,
	}
end

local function pickTarget(agent, town, config, rng, now)
	-- Decide if we go to POI or random walk
	local usePOI = (#town.pois > 0) and (rng:NextNumber() < config.POIVisitChance)

	if usePOI then
		local poiIndex = rng:NextInteger(1, #town.pois)
		agent.targetType = "POI"
		agent.targetIndex = poiIndex
		agent.targetPos = town.pois[poiIndex].pos
	else
		local nextNode = town.graph and town.graph.neighbors and town.graph.neighbors[agent.nodeIndex]
		if nextNode and #nextNode > 0 then
			local ni = nextNode[rng:NextInteger(1, #nextNode)]
			agent.targetType = "Node"
			agent.targetIndex = ni
			agent.targetPos = town.graph.nodes[ni].pos
		else
			-- fallback: pick any node
			local ni = rng:NextInteger(1, #town.graph.nodes)
			agent.targetType = "Node"
			agent.targetIndex = ni
			agent.targetPos = town.graph.nodes[ni].pos
		end
	end
end

function AgentSim.initAtGate(agent, town, config, rng, now)
	local gi = weightedPickGateIndex(town.spawnGates, rng)
	agent.homeGateIndex = gi

	if gi then
		local gate = town.spawnGates[gi]
		agent.pos = gate.pos
		agent.nodeIndex = gate.nodeIndex
		agent.state = "SpawnIn"
		agent.targetType = "Node"
		agent.targetIndex = gate.nodeIndex
		agent.targetPos = town.graph.nodes[gate.nodeIndex].pos
	else
		-- fallback: spawn at random node
		local ni = rng:NextInteger(1, #town.graph.nodes)
		agent.pos = town.graph.nodes[ni].pos
		agent.nodeIndex = ni
		agent.state = "Walk"
		agent.targetPos = nil
	end

	agent.leavingAt = now + randRange(rng, config.AgentLifetimeRange[1], config.AgentLifetimeRange[2])
end

function AgentSim.stepAgent(agent, town, config, rng, dt, now, isNear)
	-- Cheap LOD: far agents update slower and do less.
	local speed = config.WalkSpeed
	if not isNear then
		speed *= 0.9
	end

	if agent.state == "Idle" then
		if now >= agent.idleUntil then
			agent.state = "Walk"
			pickTarget(agent, town, config, rng, now)
		end
		return
	end
		-- Meetup: walking to assigned slot
	if agent.state == "MeetupGo" and agent.meetup then
		local target = agent.meetup.slotPos
		local to = target - agent.pos
		local dist = to.Magnitude

		if dist <= config.MeetupArriveRadius then
			agent.pos = Vector3.new(target.X, agent.pos.Y, target.Z)
			agent.state = "MeetupIdle"
			agent.idleUntil = agent.meetup.endAt
			return
		end

		local dir = to / dist
		agent.pos += dir * speed * dt

		-- yaw toward movement
		local desiredYaw = math.atan2(-dir.Z, dir.X)
		local dy = (desiredYaw - agent.yaw)
		dy = (dy + math.pi) % (2 * math.pi) - math.pi
		local maxTurn = config.TurnSpeed * dt
		if dy > maxTurn then dy = maxTurn end
		if dy < -maxTurn then dy = -maxTurn end
		agent.yaw += dy
		return
	end

		-- If it's time to leave (but don't interrupt meetups)
	if agent.state ~= "MeetupGo" and agent.state ~= "MeetupIdle" and now >= (agent.leavingAt or math.huge) then
		if agent.homeGateIndex and town.spawnGates and town.spawnGates[agent.homeGateIndex] then
			local gate = town.spawnGates[agent.homeGateIndex]
			agent.state = "LeaveToGate"
			agent.targetType = "Gate"
			agent.targetIndex = agent.homeGateIndex
			agent.targetPos = gate.pos
		else
			agent.leavingAt = now + 60 -- fallback delay
		end
	end

	-- Despawned: do nothing until respawn time
	if agent.state == "Despawned" then
		if now >= (agent.respawnAt or 0) then
			-- new "person" comes in
			agent.appearanceSeed = rng:NextInteger(1, 2^30)
			AgentSim.initAtGate(agent, town, config, rng, now)
		end
		return
	end
	
	-- SpawnIn: walk from gate to the first road node
	if agent.state == "SpawnIn" then
		local to = agent.targetPos - agent.pos
		local dist = to.Magnitude
		if dist <= config.SpawnGateArriveRadius then
			agent.pos = agent.targetPos
			agent.state = "Walk"
			agent.targetPos = nil
			return
		end
		local dir = to / dist
		agent.pos += dir * speed * dt
		-- yaw
		local desiredYaw = math.atan2(-dir.Z, dir.X)
		local dy = (desiredYaw - agent.yaw)
		dy = (dy + math.pi) % (2 * math.pi) - math.pi
		local maxTurn = config.TurnSpeed * dt
		if dy > maxTurn then dy = maxTurn end
		if dy < -maxTurn then dy = -maxTurn end
		agent.yaw += dy
		return
	end
	
	-- LeaveToGate: walk to gate, then vanish
	if agent.state == "LeaveToGate" then
		local to = agent.targetPos - agent.pos
		local dist = to.Magnitude
		if dist <= config.SpawnGateArriveRadius then
			agent.pos = agent.targetPos
			agent.state = "Despawned"
			agent.respawnAt = now + randRange(rng, config.AgentRespawnDelayRange[1], config.AgentRespawnDelayRange[2])
			return
		end
		local dir = to / dist
		agent.pos += dir * speed * dt
		-- yaw
		local desiredYaw = math.atan2(-dir.Z, dir.X)
		local dy = (desiredYaw - agent.yaw)
		dy = (dy + math.pi) % (2 * math.pi) - math.pi
		local maxTurn = config.TurnSpeed * dt
		if dy > maxTurn then dy = maxTurn end
		if dy < -maxTurn then dy = -maxTurn end
		agent.yaw += dy
		return
	end

	-- Meetup: idling in circle (face center)
	if agent.state == "MeetupIdle" and agent.meetup then
		if now >= agent.idleUntil then
			agent.meetup = nil
			agent.state = "Walk"
			agent.targetPos = nil
			return
		end

		local toC = agent.meetup.center - agent.pos
		toC = Vector3.new(toC.X, 0, toC.Z)
		if toC.Magnitude > 0.001 then
			local dir = toC.Unit
			local desiredYaw = math.atan2(-dir.Z, dir.X)
			local dy = (desiredYaw - agent.yaw)
			dy = (dy + math.pi) % (2 * math.pi) - math.pi
			local maxTurn = config.TurnSpeed * dt
			if dy > maxTurn then dy = maxTurn end
			if dy < -maxTurn then dy = -maxTurn end
			agent.yaw += dy
		end
		return
	end

	-- Walk toward target
	local to = agent.targetPos - agent.pos
	local dist = to.Magnitude
	if dist < 1.5 then
		-- Arrived
		if agent.targetType == "Node" and agent.targetIndex then
			agent.nodeIndex = agent.targetIndex
		end

		-- Idle a bit
		local idleA, idleB = config.IdleTimeRange[1], config.IdleTimeRange[2]
		local idle = randRange(rng, idleA, idleB)
		if agent.targetType == "POI" then
			idle *= config.POIIdleMultiplier
		end

		agent.state = "Idle"
		agent.idleUntil = now + idle
		return
	end

	-- Move
	local dir = to / dist
	agent.pos += dir * speed * dt

	-- Smooth yaw toward movement direction
	local desiredYaw = math.atan2(-dir.Z, dir.X) -- Roblox XZ to yaw
	local dy = (desiredYaw - agent.yaw)
	-- wrap to [-pi, pi]
	dy = (dy + math.pi) % (2 * math.pi) - math.pi
	local maxTurn = config.TurnSpeed * dt
	if dy > maxTurn then dy = maxTurn end
	if dy < -maxTurn then dy = -maxTurn end
	agent.yaw += dy
end

function AgentSim.ensureTarget(agent, town, config, rng, now)
	if agent.targetPos == nil then
		pickTarget(agent, town, config, rng, now)
	end
end

return AgentSim
