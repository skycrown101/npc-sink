local AgentSim = {}

local function randRange(rng, a, b)
	return a + (b - a) * rng:NextNumber()
end

local function weightedPickGateIndex(gates, rng)
	if not gates or #gates == 0 then return nil end
	local total = 0
	for _, g in ipairs(gates) do
		total += (g.weight or 1)
	end
	local r = rng:NextNumber() * total
	local acc = 0
	for i, g in ipairs(gates) do
		acc += (g.weight or 1)
		if r <= acc then
			return i
		end
	end
	return 1
end

local function weightedPickRole(roleWeights, rng)
	-- roleWeights: { {"Guard", 0.2}, {"Worker", 0.5}, ... }
	if not roleWeights or #roleWeights == 0 then
		return "Shopper"
	end
	local total = 0
	for _, row in ipairs(roleWeights) do
		total += (row[2] or 0)
	end
	if total <= 0 then
		return roleWeights[1][1] or "Shopper"
	end
	local r = rng:NextNumber() * total
	local acc = 0
	for _, row in ipairs(roleWeights) do
		acc += (row[2] or 0)
		if r <= acc then
			return row[1] or "Shopper"
		end
	end
	return roleWeights[#roleWeights][1] or "Shopper"
end

function AgentSim.assignRole(agent, town, config, rng)
	agent.role = weightedPickRole(config.RoleWeights, rng)
	return agent.role
end

function AgentSim.newAgent(id, townId, startNodeIndex, startPos, rng)
	return {
		id = id,
		townId = townId,

		-- role
		role = "Shopper",

		-- simulation state
		state = "Walk", -- Walk | Idle | SpawnIn | LeaveToGate | Despawned | MeetupGo | MeetupIdle
		nodeIndex = startNodeIndex,

		pos = startPos,
		yaw = rng:NextNumber() * math.pi * 2,

		targetType = "Node", -- Node | POI | GuardPost | Gate
		targetIndex = nil,
		targetPos = startPos,

		idleUntil = 0,

		-- visuals / misc
		appearanceSeed = rng:NextInteger(1, 2^30),
		nextTalkAt = 0,

		-- spawn gates lifetime
		homeGateIndex = nil,
		leavingAt = 0,
		respawnAt = 0,
	}
end

local function pickGuardTarget(agent, town, config, rng)
	-- 1) Patrol nodes (RoadNodes with Patrol=true)
	if town.patrolNodes and #town.patrolNodes > 0 and rng:NextNumber() < (config.GuardPatrolChance or 0.7) then
		local ni = town.patrolNodes[rng:NextInteger(1, #town.patrolNodes)]
		agent.targetType = "Node"
		agent.targetIndex = ni
		agent.targetPos = town.graph.nodes[ni].pos
		return true
	end

	-- 2) Guard posts (Hotspot Type="GuardPost")
	if town.guardPosts and #town.guardPosts > 0 and rng:NextNumber() < (config.GuardGuardPostChance or 0.25) then
		local hi = town.guardPosts[rng:NextInteger(1, #town.guardPosts)]
		agent.targetType = "GuardPost"
		agent.targetIndex = hi
		agent.targetPos = town.hotspots[hi].pos
		return true
	end

	return false
end

local function pickTarget(agent, town, config, rng, now)
	local role = agent.role or "Shopper"

	-- Guards have their own target logic
	if role == "Guard" then
		if pickGuardTarget(agent, town, config, rng) then
			return
		end

		-- guards rarely go to POIs
		local usePOI = (#town.pois > 0) and (rng:NextNumber() < (config.GuardPOIVisitChance or 0.08))
		if usePOI then
			local poiIndex = rng:NextInteger(1, #town.pois)
			agent.targetType = "POI"
			agent.targetIndex = poiIndex
			agent.targetPos = town.pois[poiIndex].pos
			return
		end
		-- else fall through to random road walking
	end

	-- Default behavior (workers/shoppers/anyone else):
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
		local ni = rng:NextInteger(1, #town.graph.nodes)
		agent.pos = town.graph.nodes[ni].pos
		agent.nodeIndex = ni
		agent.state = "Walk"
		agent.targetPos = nil
	end

	agent.leavingAt = now + randRange(rng, config.AgentLifetimeRange[1], config.AgentLifetimeRange[2])
end

local function yawToward(agent, dir, dt, turnSpeed)
	local desiredYaw = math.atan2(-dir.Z, dir.X)
	local dy = (desiredYaw - agent.yaw)
	dy = (dy + math.pi) % (2 * math.pi) - math.pi
	local maxTurn = turnSpeed * dt
	if dy > maxTurn then dy = maxTurn end
	if dy < -maxTurn then dy = -maxTurn end
	agent.yaw += dy
end

function AgentSim.stepAgent(agent, town, config, rng, dt, now, isNear)
	local speed = config.WalkSpeed
	if not isNear then
		speed *= 0.9
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
			agent.leavingAt = now + 60
		end
	end

	-- Despawned: do nothing until respawn time
	if agent.state == "Despawned" then
		if now >= (agent.respawnAt or 0) then
			agent.appearanceSeed = rng:NextInteger(1, 2^30)
			AgentSim.assignRole(agent, town, config, rng) -- new person can have new role
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
		yawToward(agent, dir, dt, config.TurnSpeed)
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
		yawToward(agent, dir, dt, config.TurnSpeed)
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
		yawToward(agent, dir, dt, config.TurnSpeed)
		return
	end

	-- Meetup: idling (face center)
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
			yawToward(agent, toC.Unit, dt, config.TurnSpeed)
		end
		return
	end

	-- Normal idle
	if agent.state == "Idle" then
		if now >= agent.idleUntil then
			agent.state = "Walk"
			pickTarget(agent, town, config, rng, now)
		end
		return
	end

	-- Ensure we have a target
	if agent.targetPos == nil then
		pickTarget(agent, town, config, rng, now)
	end

	-- Walk toward target
	local to = agent.targetPos - agent.pos
	local dist = to.Magnitude

	if dist < 1.5 then
		-- Arrived
		if agent.targetType == "Node" and agent.targetIndex then
			agent.nodeIndex = agent.targetIndex
		end

		local idleA, idleB = config.IdleTimeRange[1], config.IdleTimeRange[2]
		local idle = randRange(rng, idleA, idleB)

		if agent.targetType == "POI" then
			idle *= config.POIIdleMultiplier
		elseif agent.targetType == "GuardPost" then
			idle *= (config.GuardPostIdleMultiplier or 1.2)
		end

		agent.state = "Idle"
		agent.idleUntil = now + idle
		return
	end

	local dir = to / dist
	agent.pos += dir * speed * dt
	yawToward(agent, dir, dt, config.TurnSpeed)
end

function AgentSim.ensureTarget(agent, town, config, rng, now)
	if agent.targetPos == nil then
		pickTarget(agent, town, config, rng, now)
	end
end

return AgentSim
