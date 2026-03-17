local EventSim = {}

local function randRange(rng, a, b)
	return a + (b - a) * rng:NextNumber()
end

local function clamp01(x)
	if x < 0 then return 0 end
	if x > 1 then return 1 end
	return x
end

local function getHotspotCapacity(hotspot, config)
	local cap = hotspot.inst:GetAttribute("Capacity")
	if typeof(cap) == "number" then
		return math.max(1, math.floor(cap))
	end
	return config.HotspotDefaultCapacity
end

local function getHotspotRadius(hotspot, config)
	local r = hotspot.inst:GetAttribute("Radius")
	if typeof(r) == "number" then
		return math.max(1, r)
	end
	return config.HotspotDefaultRadius
end

local function getFormation(hotspot)
	local f = hotspot.inst:GetAttribute("Formation")
	if typeof(f) == "string" and f ~= "" then
		return f
	end
	return "Circle"
end

local function getQueueSpacing(hotspot, config)
	local s = hotspot.inst:GetAttribute("QueueSpacing")
	if typeof(s) == "number" and s > 0.5 then
		return s
	end
	return config.QueueSpacingDefault or 2.4
end

local function getQueueSideJitter(hotspot, config)
	local j = hotspot.inst:GetAttribute("QueueSideJitter")
	if typeof(j) == "number" and j >= 0 then
		return j
	end
	return config.QueueSideJitterDefault or 0.35
end

function EventSim.initTown(town, config, now)
	town._events = {}
	town._nextEventId = 1
	town._nextMeetupAt = now + randRange(town.rng, config.MeetupCooldownRange[1], config.MeetupCooldownRange[2])
end

local function endMeetup(town, event)
	for _, agentId in ipairs(event.participants) do
		local agent = town._agentById[agentId]
		if agent then
			agent.meetup = nil
			agent.state = "Walk"
			agent.targetPos = nil
		end
	end
end

local function cleanupExpiredEvents(town, now)
	if not town._events then return end

	local keep = {}
	for _, ev in ipairs(town._events) do
		if now >= ev.endAt then
			endMeetup(town, ev)
		else
			table.insert(keep, ev)
		end
	end
	town._events = keep
end

local function countActiveMeetups(town)
	if not town._events then return 0 end
	return #town._events
end

local function pickHotspotNearFocus(town, config, rng, focusPos)
	if not town.hotspots or #town.hotspots == 0 then
		return nil
	end

	local candidates = {}
	for _, hs in ipairs(town.hotspots) do
		local d = (hs.pos - focusPos).Magnitude
		if d <= config.MeetupSpawnRadius then
			table.insert(candidates, { hs = hs, d = d })
		end
	end

	if #candidates == 0 then
		return nil
	end

	-- bias toward closer hotspots
	local totalW = 0
	for _, c in ipairs(candidates) do
		c.w = 0.2 + 0.8 * (1 - clamp01(c.d / config.MeetupSpawnRadius))
		totalW += c.w
	end

	local roll = rng:NextNumber() * totalW
	local acc = 0
	for _, c in ipairs(candidates) do
		acc += c.w
		if roll <= acc then
			return c.hs
		end
	end

	return candidates[#candidates].hs
end

local function pickAgentsForMeetup(town, config, rng, hotspot, desiredCount)
	local scored = {}
	for _, agent in ipairs(town.agents) do
		if agent.meetup == nil and agent.state ~= "MeetupGo" and agent.state ~= "MeetupIdle" then
			local d = (agent.pos - hotspot.pos).Magnitude
			table.insert(scored, { agent = agent, d = d })
		end
	end

	if #scored == 0 then
		return {}
	end

	table.sort(scored, function(a, b)
		return a.d < b.d
	end)

	local cap = math.min(getHotspotCapacity(hotspot, config), desiredCount)

	local picked = {}
	for i = 1, math.min(cap, #scored) do
		table.insert(picked, scored[i].agent)
	end
	return picked
end

-- Circle meetup slots (existing behavior)
local function assignCircleSlots(town, config, rng, hotspot, agents)
	local center = hotspot.pos
	local n = #agents
	if n == 0 then return end

	local baseR = config.MeetupCircleRadius
	local hsR = getHotspotRadius(hotspot, config)
	local r = math.max(2.5, math.min(baseR, hsR)) + rng:NextNumber() * config.MeetupCircleJitter

	local startAngle = rng:NextNumber() * math.pi * 2

	for i, agent in ipairs(agents) do
		local a = startAngle + (i - 1) * (2 * math.pi / n)
		local slotPos = Vector3.new(
			center.X + math.cos(a) * r,
			center.Y,
			center.Z + math.sin(a) * r
		)

		agent.meetup = {
			-- AgentSim uses meetup.center as the look-at point while idling
			center = center,
			slotPos = slotPos,
			endAt = nil,
			eventId = nil,
			formation = "Circle",
		}
	end
end

-- Queue meetup slots (new)
local function assignQueueSlots(town, config, rng, hotspot, agents)
	local center = hotspot.pos
	local n = #agents
	if n == 0 then return end

	-- Use hotspot part orientation if possible
	local forward = Vector3.new(0, 0, -1)
	if hotspot.inst and hotspot.inst:IsA("BasePart") then
		forward = hotspot.inst.CFrame.LookVector
		forward = Vector3.new(forward.X, 0, forward.Z)
		if forward.Magnitude < 0.001 then
			forward = Vector3.new(0, 0, -1)
		else
			forward = forward.Unit
		end
	end

	local right = Vector3.new(-forward.Z, 0, forward.X)

	local spacing = getQueueSpacing(hotspot, config)
	local sideJitter = getQueueSideJitter(hotspot, config)

	-- look-at point (so they face toward the “front” of the queue)
	local lookAt = center + forward * math.max(4, spacing * 2)

	-- Front person stands closest to the center, others behind them
	for i, agent in ipairs(agents) do
		local behind = (i - 1) * spacing
		local lateral = (rng:NextNumber() * 2 - 1) * sideJitter

		local slotPos = center - forward * behind + right * lateral
		slotPos = Vector3.new(slotPos.X, center.Y, slotPos.Z)

		agent.meetup = {
			center = lookAt, -- face forward while idling
			slotPos = slotPos,
			endAt = nil,
			eventId = nil,
			formation = "Queue",
		}
	end
end

function EventSim.trySpawnMeetup(town, config, now, focusPos)
	if not config.MeetupsEnabled then return end
	if not town.hotspots or #town.hotspots == 0 then return end
	if now < (town._nextMeetupAt or 0) then return end

	if countActiveMeetups(town) >= config.MaxActiveMeetupsPerTown then
		town._nextMeetupAt = now + 2
		return
	end

	local hotspot = pickHotspotNearFocus(town, config, town.rng, focusPos)
	if not hotspot then
		town._nextMeetupAt = now + 3
		return
	end

	local minN, maxN = config.MeetupGroupSizeRange[1], config.MeetupGroupSizeRange[2]
	local desiredCount = town.rng:NextInteger(minN, maxN)

	local agents = pickAgentsForMeetup(town, config, town.rng, hotspot, desiredCount)
	if #agents < minN then
		town._nextMeetupAt = now + randRange(town.rng, config.MeetupCooldownRange[1], config.MeetupCooldownRange[2])
		return
	end

	local duration = randRange(town.rng, config.MeetupDurationRange[1], config.MeetupDurationRange[2])
	local eventId = town._nextEventId
	town._nextEventId += 1

	-- Choose formation
	local formation = getFormation(hotspot)
	if formation == "Queue" then
		assignQueueSlots(town, config, town.rng, hotspot, agents)
	else
		assignCircleSlots(town, config, town.rng, hotspot, agents)
	end

	local participants = {}
	for _, agent in ipairs(agents) do
		table.insert(participants, agent.id)
		agent.state = "MeetupGo"
		agent.targetPos = agent.meetup.slotPos
		agent.meetup.endAt = now + duration
		agent.meetup.eventId = eventId
	end

	-- Speaker + talk budget (existing system)
	local speaker = agents[town.rng:NextInteger(1, #agents)]
	local linesLeft = town.rng:NextInteger(config.MeetupLinesPerMeetupRange[1], config.MeetupLinesPerMeetupRange[2])
	local nextLineAt = now + town.rng:NextNumber()

	table.insert(town._events, {
		id = eventId,
		type = "Meetup",
		hotspot = hotspot,
		participants = participants,
		startAt = now,
		endAt = now + duration,

		formation = formation,

		speakerId = speaker.id,
		linesLeft = linesLeft,
		nextLineAt = nextLineAt,
		pending = {},
	})

	town._nextMeetupAt = now + randRange(town.rng, config.MeetupCooldownRange[1], config.MeetupCooldownRange[2])
end

function EventSim.updateTown(town, config, now, focusPos)
	if not town._events then
		EventSim.initTown(town, config, now)
	end
	cleanupExpiredEvents(town, now)
	EventSim.trySpawnMeetup(town, config, now, focusPos)
end

return EventSim
