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

function EventSim.initTown(town, config, now)
	town._events = {}
	town._nextEventId = 1
	town._nextMeetupAt = now + randRange(town.rng, config.MeetupCooldownRange[1], config.MeetupCooldownRange[2])
end

local function endMeetup(town, config, now, event)
	-- release agents back to normal walking
	for _, agentId in ipairs(event.participants) do
		local agent = town._agentById[agentId]
		if agent then
			agent.meetup = nil
			agent.state = "Walk"
			-- Ensure they get a new target next sim step
			agent.targetPos = nil
		end
	end
end

local function cleanupExpiredEvents(town, config, now)
	if not town._events then return end
	local keep = {}
	for _, ev in ipairs(town._events) do
		if now >= ev.endAt then
			endMeetup(town, config, now, ev)
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
			table.insert(candidates, {hs = hs, d = d})
		end
	end
	if #candidates == 0 then
		return nil
	end

	-- Slight bias toward closer hotspots so you usually see the meetup
	-- Weight = 1 - (d/r)
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
	-- Choose nearby free agents (not already in a meetup)
	local scored = {}
	for _, agent in ipairs(town.agents) do
		if agent.meetup == nil and agent.state ~= "MeetupGo" and agent.state ~= "MeetupIdle" then
			local d = (agent.pos - hotspot.pos).Magnitude
			table.insert(scored, {agent = agent, d = d})
		end
	end

	if #scored == 0 then return {} end
	table.sort(scored, function(a, b) return a.d < b.d end)

	-- Respect hotspot capacity
	local cap = math.min(getHotspotCapacity(hotspot, config), desiredCount)

	local picked = {}
	for i = 1, math.min(cap, #scored) do
		table.insert(picked, scored[i].agent)
	end
	return picked
end

local function assignCircleSlots(town, config, rng, hotspot, agents)
	local center = hotspot.pos
	local n = #agents
	if n == 0 then return end

	-- radius can vary a little; also respect hotspot radius so groups don’t overlap walls as much
	local baseR = config.MeetupCircleRadius
	local hsR = getHotspotRadius(hotspot, config)
	local r = math.max(2.5, math.min(baseR, hsR)) + rng:NextNumber() * config.MeetupCircleJitter

	local startAngle = rng:NextNumber() * math.pi * 2
	for i, agent in ipairs(agents) do
		local a = startAngle + (i - 1) * (2 * math.pi / n)

		-- Keep y at hotspot height (simple). If your towns have slopes, you can raycast here later.
		local slotPos = Vector3.new(
			center.X + math.cos(a) * r,
			center.Y,
			center.Z + math.sin(a) * r
		)

		agent.meetup = {
			center = center,
			slotPos = slotPos,
			endAt = nil, -- filled in later
			eventId = nil,
		}
	end
end

function EventSim.trySpawnMeetup(town, config, now, focusPos)
	if not config.MeetupsEnabled then return end
	if not town.hotspots or #town.hotspots == 0 then return end

	if now < (town._nextMeetupAt or 0) then return end
	if countActiveMeetups(town) >= config.MaxActiveMeetupsPerTown then
		-- push next attempt slightly forward so we don't spam
		town._nextMeetupAt = now + 2
		return
	end

	local hotspot = pickHotspotNearFocus(town, config, town.rng, focusPos)
	if not hotspot then
		-- no visible hotspots near player right now; try later
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

	-- Build event
	local duration = randRange(town.rng, config.MeetupDurationRange[1], config.MeetupDurationRange[2])
	local eventId = town._nextEventId
	town._nextEventId += 1

	assignCircleSlots(town, config, town.rng, hotspot, agents)

	local participants = {}
	for _, agent in ipairs(agents) do
		table.insert(participants, agent.id)
		agent.state = "MeetupGo"
		agent.targetPos = agent.meetup.slotPos
		agent.meetup.endAt = now + duration
		agent.meetup.eventId = eventId
	end

	table.insert(town._events, {
		id = eventId,
		type = "Meetup",
		hotspot = hotspot,
		participants = participants,
		startAt = now,
		endAt = now + duration,
	})

	town._nextMeetupAt = now + randRange(town.rng, config.MeetupCooldownRange[1], config.MeetupCooldownRange[2])
end

function EventSim.updateTown(town, config, now, focusPos)
	if not town._events then
		EventSim.initTown(town, config, now)
	end

	cleanupExpiredEvents(town, config, now)
	EventSim.trySpawnMeetup(town, config, now, focusPos)
end

return EventSim
