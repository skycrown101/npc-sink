# npc-sink (TownLife)

This spawns “town life” NPCs in Roblox.

You place a few invisible marker parts (town zone, road nodes, hotspots, spawn gates). Then it spawns simple NPCs that:
- walk around on roads
- sometimes stop at POIs
- sometimes group up at hotspots and talk
- enter/leave through gates (so they don’t pop in)

It runs on the client and the NPCs are not Humanoids (they’re lightweight, R6-shaped part models).

## How to use

Copy these into your place:
- `ReplicatedStorage/TownLife/`
- `StarterPlayer/StarterPlayerScripts/TownLife.client.lua`

Press Play.
- F6 = stop
- F7 = start

Everything it spawns goes under `Workspace.__TownLife`.

## Markers (Tag Editor)

Make small anchored Parts (CanCollide off, Transparency 1 recommended).
Tag them and set Attributes.

### Required

**TownZone**
- Tag: `TownZone`
- Attributes:
  - `TownId` (string) example: `TownA`
  - `PopulationCap` (number, optional)

**RoadNode**
- Tag: `RoadNode`
- Attributes:
  - `TownId` (string)
  - `Links` (string, optional) example: `Node01,Node02`
    - If you don’t use `Links`, nearby nodes auto-connect (see `AutoLinkDistance` in Config).

### Optional (recommended)

**POI**
- Tag: `POI`
- Attributes:
  - `TownId` (string)
  - `Type` (string) example: `Market`, `Inn`, `Home`, `Work`

**Hotspot** (group meetups + talking)
- Tag: `Hotspot`
- Attributes:
  - `TownId` (string)
  - `Type` (string) example: `Tavern`, `Fountain`, `Market`
  - `Capacity` (number, optional)
  - `Radius` (number, optional)

**SpawnGate** (enter/leave)
- Tag: `SpawnGate`
- Attributes:
  - `TownId` (string)
  - `Weight` (number, optional) higher = used more
  - `Node` (string, optional) name of a RoadNode to connect to
    - If Node isn’t set, it uses the nearest road node.
  - `Formation` (string, optional): `Circle` (default) or `Queue`
  - `QueueSpacing` (number, optional): spacing between people in a queue
  - `QueueSideJitter` (number, optional): small sideways randomness so the line isn’t perfect
Tip: rotate the Hotspot part to aim the queue direction (it uses the part’s forward direction).
## Bubble talk

Meetup talk uses Roblox bubble chat (`TextChatService:DisplayBubble`).

To see bubbles:
- enable Bubble Chat in your game settings
OR
- set `AutoEnableBubbleChat = true` in `Config.lua`.

## Settings

Edit `ReplicatedStorage/TownLife/Config.lua` to change:
- population cap
- max visible NPCs
- distances
- meetup size/frequency
- dialogue frequency
- spawn gate timing

Edit `ReplicatedStorage/TownLife/Dialogue.lua` to add more hotspot types + lines.
