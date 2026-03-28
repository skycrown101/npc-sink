local Config = {}

-- Hard caps (performance knobs)
Config.MaxAgentsPerTownDefault = 40
Config.MaxVisibleNPCs = 20 -- only this many models render near the camera
Config.VisibleDistance = 140 -- studs: within this distance agents are eligible to render
Config.DespawnDistance = 220 -- studs: beyond this, we usually won't render

-- Movement / sim
Config.WalkSpeed = 10 -- studs/sec for fake movement
Config.TurnSpeed = 10 -- radians/sec for yaw smoothing
Config.SimHzNear = 10 -- sim update rate for nearby (agents/sec)
Config.SimHzFar = 2 -- sim update rate for far agents (data-only)
Config.IdleTimeRange = { 1.5, 5.0 } -- seconds

-- Graph building
Config.AutoLinkDistance = 60 -- studs: RoadNodes within this are linked (if no Links attribute)
Config.MaxNeighborLinks = 6 -- keep graph from becoming too dense

-- POI behavior
Config.POIVisitChance = 0.45 -- chance next target is a POI instead of a random walk
Config.POIIdleMultiplier = 1.6 -- idle longer at POIs

-- Debug
Config.DebugDraw = false -- prints + optional gizmos later

-- Meetups / hotspots
Config.MeetupsEnabled = true
Config.MaxActiveMeetupsPerTown = 2

Config.MeetupSpawnRadius = 180 -- only spawn meetups near the player/camera
Config.MeetupGroupSizeRange = { 3, 6 }
Config.MeetupDurationRange = { 7, 14 } -- seconds
Config.MeetupCooldownRange = { 8, 18 } -- seconds between meetup spawns (per town)

Config.MeetupArriveRadius = 2.5 -- studs
Config.MeetupCircleRadius = 4.0 -- studs (ring around hotspot)
Config.MeetupCircleJitter = 0.6 -- random offset to avoid perfect symmetry

Config.HotspotDefaultCapacity = 6
Config.HotspotDefaultRadius = 10

-- Dialogue / bubbles
Config.DialogueEnabled = true
Config.DialogueMeetupOnly = true
Config.DialogueAdorneePartName = "Head"

Config.DialogueTalkChance = 0.65
Config.DialogueTalkIntervalRange = { 2.0, 4.5 } -- seconds

Config.AutoEnableBubbleChat = false

-- Meetup dialogue behavior
Config.MeetupTalkEnabled = true
Config.MeetupLinesPerMeetupRange = { 2, 5 }
Config.MeetupSpeakerLineIntervalRange = { 1.8, 3.2 }
Config.MeetupReactionChance = 0.55
Config.MeetupReactionDelayRange = { 0.25, 0.9 }

-- Spawn Gates (enter/leave illusion)
Config.SpawnGatesEnabled = true
Config.SpawnGateArriveRadius = 2.5

-- NPC "lifetime" (they leave town via a gate, vanish, then re-enter later)
Config.AgentLifetimeRange = { 60, 180 } -- seconds before they leave
Config.AgentRespawnDelayRange = { 3, 12 } -- seconds before they re-enter

-- When despawned, don't render them and don't simulate movement
Config.DespawnedAgentsDoNothing = true

Config.VisibilityRefreshInterval = 0.25 -- seconds
Config.FarSimBudgetPerTick = 40 -- how many far agents to advance each far tick

-- Queue hotspot defaults
Config.QueueSpacingDefault = 2.4
Config.QueueSideJitterDefault = 0.35

Config.RoleWeights = {
	{"Guard", 0.18},
	{"Worker", 0.42},
	{"Shopper", 0.40},
}

-- Guard behavior
Config.GuardPatrolChance = 0.70       -- how often guards pick patrol nodes
Config.GuardPOIVisitChance = 0.08     -- guards rarely visit POIs
Config.GuardGuardPostChance = 0.25    -- sometimes go to guard posts
Config.GuardPostIdleMultiplier = 1.4

-- Identity / labels
Config.ShowNameLabels = true
Config.ShowRoleLabels = true
Config.NameLabelMaxDistance = 90
Config.NameLabelStudsOffset = 3.2
Config.NameLabelWidth = 140
Config.NameLabelHeight = 34
Config.NameLabelsAlwaysOnTop = true

-- Optional override pools for Names.lua (leave nil to use defaults)
Config.NamePoolFirst = nil
Config.NamePoolLast = nil

Config.NameLabelRefreshInterval = 0.25

-- Role-driven visual styling
Config.RoleVisuals = {
	Guard = {
		BodyColor = Color3.fromRGB(85, 92, 104),
		AccentColor = Color3.fromRGB(196, 61, 61),
		LabelColor = Color3.fromRGB(255, 236, 176),
		HatTransparency = 0,
	},
	Worker = {
		BodyColor = Color3.fromRGB(152, 111, 72),
		AccentColor = Color3.fromRGB(228, 176, 73),
		LabelColor = Color3.fromRGB(236, 236, 236),
		HatTransparency = 0.2,
	},
	Shopper = {
		AccentColor = Color3.fromRGB(125, 105, 235),
		LabelColor = Color3.fromRGB(236, 236, 236),
		HatTransparency = 0,
	},
}

-- roles
Config.RoleWeights = {
	{"Guard", 0.18},
	{"Worker", 0.52},
	{"Shopper", 0.30},
}

Config.GuardPatrolChance = 0.72
Config.GuardGuardPostChance = 0.22
Config.GuardPOIVisitChance = 0.06
Config.GuardPostIdleMultiplier = 1.35

-- schedules
Config.ScheduleEnabled = true
Config.ScheduleCheckInterval = 3.0

Config.ScheduleByRole = {
	Guard = {
		{0, 6, "GuardPost"},
		{6, 12, "Patrol"},
		{12, 18, "GuardPost"},
		{18, 24, "Patrol"},
	},

	Worker = {
		{0, 7, "Home"},
		{7, 17, "Work"},
		{17, 20, "Market"},
		{20, 24, "Home"},
	},

	Shopper = {
		{0, 8, "Home"},
		{8, 18, "Market"},
		{18, 22, "Hotspot"},
		{22, 24, "Home"},
	},
}

-- simple needs
Config.NeedsEnabled = true
Config.NeedDecayPerMinute = {
	Hunger = 7,
	Energy = 5,
	Social = 6,
}

Config.NeedThresholds = {
	Hunger = 35,
	Energy = 30,
	Social = 32,
}

Config.NeedTargetTypes = {
	Hunger = "Market",
	Energy = "Home",
	Social = "Hotspot",
}

return Config
