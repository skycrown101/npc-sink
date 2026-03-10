# npc-sink (TownLife)

This is a “town life” system for Roblox.

You place a few invisible marker parts (town zone, road nodes, hotspots, etc) and it spawns simple NPCs that:
- walk around on the roads
- sometimes stop at POIs
- sometimes group up at hotspots and “talk”
- enter/leave through spawn gates (so they don’t just pop in)

It runs on the **client** and the NPCs are **not Humanoids** (they’re lightweight, R6-shaped part models).

---

## How to use

Copy these into your place:
- `ReplicatedStorage/TownLife/`
- `StarterPlayer/StarterPlayerScripts/TownLife.client.lua`

Press Play.
- F6 = stop
- F7 = start

Everything it spawns goes under `Workspace.__TownLife`.

---

## Markers you place (Tag Editor)

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
    - If you don’t use Links, nearby nodes auto-connect (see `AutoLinkDistance` in Config).

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

**SpawnGate** (enter/leave illusion)
- Tag: `SpawnGate`
- Attributes:
  - `TownId` (string)
  - `Weight` (number, optional) higher = used more
  - `Node` (string, optional) name of a RoadNode to connect to
    - If Node isn’t set, it uses the nearest road node.

---

## Bubble talk

Meetup talk uses Roblox bubble chat (`TextChatService:DisplayBubble`).

To see bubbles:
- enable Bubble Chat in your game settings,
OR
- set `AutoEnableBubbleChat = true` in `Config.lua`.

---

## Settings

Edit `ReplicatedStorage/TownLife/Config.lua` to change:
- population cap
- max visible NPCs
- distances
- meetup size/frequency
- dialogue frequency
- spawn gate timing (leave/respawn)

Edit `ReplicatedStorage/TownLife/Dialogue.lua` to add more hotspot types + lines.
