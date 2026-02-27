local Config = {}

-- Hard caps (performance knobs)
Config.MaxAgentsPerTownDefault = 40
Config.MaxVisibleNPCs = 20           -- only this many models render near the camera
Config.VisibleDistance = 140         -- studs: within this distance agents are eligible to render
Config.DespawnDistance = 220         -- studs: beyond this, we usually won't render

-- Movement / sim
Config.WalkSpeed = 10               -- studs/sec for fake movement
Config.TurnSpeed = 10               -- radians/sec for yaw smoothing
Config.SimHzNear = 10               -- sim update rate for nearby (agents/sec)
Config.SimHzFar = 2                 -- sim update rate for far agents (data-only)
Config.IdleTimeRange = {1.5, 5.0}   -- seconds

-- Graph building
Config.AutoLinkDistance = 60        -- studs: RoadNodes within this are linked (if no Links attribute)
Config.MaxNeighborLinks = 6         -- keep graph from becoming too dense

-- POI behavior
Config.POIVisitChance = 0.45        -- chance next target is a POI instead of a random walk
Config.POIIdleMultiplier = 1.6      -- idle longer at POIs

-- Debug
Config.DebugDraw = false            -- prints + optional gizmos later

return Config
