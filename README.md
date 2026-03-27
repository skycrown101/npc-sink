# npc-sink (TownLife)

Lightweight client-side “town life” NPC simulation for Roblox.

You place a few invisible marker parts (town zones, road nodes, POIs, hotspots, and optional spawn gates), and the system spawns simple fake NPCs that:

- walk along road graphs
- sometimes stop at POIs
- sometimes gather at hotspots and talk with bubble chat
- can enter/leave through spawn gates so they do not just pop in
- use lightweight part-based models instead of Humanoids

Everything runs on the client. NPCs are not real Humanoid characters, which keeps the system much cheaper than full character AI.

---

## What it does

TownLife builds one or more towns from tagged marker parts, then simulates a population per town.

NPCs can:

- roam between road nodes
- visit POIs
- gather into meetup groups at hotspots
- speak using contextual bubble dialogue
- despawn and re-enter through gates
- take different roles like `Guard`, `Worker`, and `Shopper`

The renderer only keeps a limited number of nearby NPCs visually active at once.

---

## Performance model

This system is designed to stay lightweight.

### Key runtime behavior

- **Client-side only**
- **Part-based R6-style fake NPCs**
- **Global visible cap**
  - only the nearest NPCs inside `Config.MaxVisibleNPCs` are rendered
- **Global far-sim budget**
  - far-away NPCs are simulated using a fixed budget per far tick
- **Model pooling**
  - visual models are reused instead of recreated
- **Throttled name labels**
  - label visibility checks should be limited instead of updated every frame

### Why this matters

With multiple towns, the system does **not** try to fully render every NPC. It chooses the nearest visible NPCs globally, keeps those rendered, and steps the rest more cheaply in the background.

---

## Install

Copy these into your place:

- `ReplicatedStorage/TownLife/`
- `StarterPlayer/StarterPlayerScripts/TownLife.client.lua`

Then press **Play**.

### Test hotkeys

- `F6` = stop
- `F7` = start

Spawned visuals go under:

- `Workspace.__TownLife`

---

## Required marker setup

Make small anchored Parts and usually set:

- `Anchored = true`
- `CanCollide = false`
- `Transparency = 1`

Then tag them with Roblox Tag Editor and add the attributes below.

---

## Tags and attributes

### `TownZone`
Defines a town and optional population cap.

**Tag**
- `TownZone`

**Attributes**
- `TownId` (`string`)  
  Example: `TownA`
- `PopulationCap` (`number`, optional)

---

### `RoadNode`
Defines the road/path graph for a town.

**Tag**
- `RoadNode`

**Attributes**
- `TownId` (`string`)
- `Links` (`string`, optional)  
  Example: `Node01,Node02`
- `Patrol` (`boolean`, optional)  
  If `true`, guards can use this as a patrol node.

If `Links` is not provided, nearby nodes can auto-connect using `Config.AutoLinkDistance`.

---

## Optional markers

### `POI`
Places NPCs may walk to and idle at.

**Tag**
- `POI`

**Attributes**
- `TownId` (`string`)
- `Type` (`string`, optional)  
  Example: `Market`, `Inn`, `Home`, `Work`

---

### `Hotspot`
Used for group meetups and bubble-chat conversations.

**Tag**
- `Hotspot`

**Attributes**
- `TownId` (`string`)
- `Type` (`string`, optional)  
  Example: `Tavern`, `Fountain`, `Market`, `GuardPost`
- `Capacity` (`number`, optional)
- `Radius` (`number`, optional)

### Hotspot queue settings
These belong on the **Hotspot**, not the gate.

- `Formation` (`string`, optional)  
  `Circle` (default) or `Queue`
- `QueueSpacing` (`number`, optional)  
  spacing between people in the queue
- `QueueSideJitter` (`number`, optional)  
  slight sideways randomness so the line is not perfectly straight

**Tip:** rotate the Hotspot part to aim the queue direction. Queue formation uses the hotspot part’s forward direction.

---

### `SpawnGate`
Used for enter/leave behavior.

**Tag**
- `SpawnGate`

**Attributes**
- `TownId` (`string`)
- `Weight` (`number`, optional)  
  higher = picked more often
- `Node` (`string`, optional)  
  name of the `RoadNode` this gate should connect to

If `Node` is not set, TownLife uses the nearest road node.

---

## Roles

The default system supports these roles through `Config.RoleWeights`:

- `Guard`
- `Worker`
- `Shopper`

### Guard behavior
Guards can:

- patrol road nodes with `Patrol = true`
- visit `Hotspot`s with `Type = "GuardPost"`
- occasionally visit regular POIs

You can tune this in `Config.lua`.

---

## Bubble talk

Meetup dialogue uses Roblox bubble chat through `TextChatService:DisplayBubble`.

To see bubbles:

- enable Bubble Chat in your game settings  
or
- set `AutoEnableBubbleChat = true` in `Config.lua`

Dialogue content is driven by hotspot type packs in:

- `ReplicatedStorage/TownLife/Dialogue.lua`

You can add more hotspot types and custom lines there.

---

## Main settings

Edit `ReplicatedStorage/TownLife/Config.lua` to tune behavior.

Common settings include:

### Population / rendering
- `MaxAgentsPerTownDefault`
- `MaxVisibleNPCs`
- `VisibleDistance`
- `DespawnDistance`

### Simulation
- `WalkSpeed`
- `TurnSpeed`
- `SimHzNear`
- `SimHzFar`
- `FarSimBudgetPerTick`
- `VisibilityRefreshInterval`

### POIs / meetups
- `POIVisitChance`
- `MeetupsEnabled`
- `MaxActiveMeetupsPerTown`
- `MeetupSpawnRadius`
- `MeetupGroupSizeRange`
- `MeetupDurationRange`
- `MeetupCooldownRange`

### Spawn gates
- `SpawnGatesEnabled`
- `SpawnGateArriveRadius`
- `AgentLifetimeRange`
- `AgentRespawnDelayRange`

### Labels / visuals
- `ShowNameLabels`
- `ShowRoleLabels`
- `NameLabelMaxDistance`
- `NameLabelWidth`
- `NameLabelHeight`
- `NameLabelsAlwaysOnTop`
- `RoleVisuals`

If you added throttled label refresh in `Renderer.lua`, you can also expose:

- `NameLabelRefreshInterval`

---

## Notes

- This is a **fake crowd / ambience** system, not full server-authoritative NPC AI.
- NPCs are intended for visual life and lightweight ambient behavior.
- Since it runs on the client, each player simulates their own local town-life view.
- The system works best when your roads, POIs, hotspots, and gates are laid out cleanly and tagged correctly.

---

## Recommended setup tips

- Keep marker parts small and invisible
- Make sure every town marker shares the same `TownId`
- Use enough `RoadNode`s to define believable movement
- Add at least one `Hotspot` if you want group talking
- Add `SpawnGate`s if you want more natural enter/leave flow
- Turn off name labels if you want the best performance

---

## Troubleshooting

### Nothing spawns
Check that:

- `TownZone` exists
- at least 2 `RoadNode`s exist for the town
- all required markers have a valid `TownId`

### NPCs do not talk
Check that:

- `MeetupsEnabled = true`
- `DialogueEnabled = true`
- `MeetupTalkEnabled = true`
- Bubble Chat is enabled or auto-enabled

### Queues are not forming correctly
Check that:

- `Formation = "Queue"` is set on the **Hotspot**
- the Hotspot part is rotated the way you want the queue to face

### NPCs pop in too much
Add or tune:

- `SpawnGate`s
- `Weight`
- `Node`
- `AgentLifetimeRange`
- `AgentRespawnDelayRange`

---

## File overview

- `TownLife.lua`  
  main runtime loop, visibility selection, near/far sim
- `AgentSim.lua`  
  agent movement/state logic
- `Renderer.lua`  
  pooled fake NPC models and visual updates
- `EventSim.lua`  
  hotspot meetup spawning/management
- `Dialogue.lua`  
  meetup bubble dialogue
- `Graph.lua`  
  road graph building
- `Config.lua`  
  tuning values
