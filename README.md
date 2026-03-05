# NPC Sink (TownLife)

This is a “town life” system for Roblox, work in progress and not meant to be used currently

You mark out a town with a few invisible parts (zones, road points, hotspots, etc). Then it spawns simple NPCs that:
- walk around on the roads
- sometimes stop at points of interest
- sometimes group up at hotspots and “talk”
- enter/leave through spawn gates (so they don’t just pop in)

It runs on the **client** and the NPCs are **not Humanoids** (they’re lightweight, R6-shaped part models). :contentReference[oaicite:0]{index=0}

---

## Drop it into a place

Copy these folders into your place:
- `ReplicatedStorage/TownLife/`
- `StarterPlayer/StarterPlayerScripts/TownLife.client.lua` :contentReference[oaicite:1]{index=1}

The system spawns everything under `Workspace.__TownLife` so it’s easy to delete/clean up.

---

## What you place in the world (the markers)

Use **Tag Editor** in Studio (View, Tag Editor). Make small anchored parts (CanCollide off, Transparency 1 recommended), tag them, and set Attributes.

### Required
**TownZone**
- Tag: `TownZone`
- Attributes:
  - `TownId` (string) — example: `TownA`
  - `PopulationCap` (number, optional)

**RoadNode**
- Tag: `RoadNode`
- Attributes:
  - `TownId` (string)
  - `Links` (string, optional): `"NodeName1,NodeName2"` (manual connections)
    - If you don’t use `Links`, nearby nodes auto-connect based on `AutoLinkDistance` in `Config.lua`. :contentReference[oaicite:3]{index=3}

### Optional (but makes it feel way more alive)
**POI (points of interest)**
- Tag: `POI`
- Attributes:
  - `TownId` (string)
  - `Type` (string) — example: `Market`, `Inn`, `Home`, `Work`

NPCs sometimes walk to these and idle longer there. :contentReference[oaicite:4]{index=4}

**Hotspot (meetups)**
- Tag: `Hotspot`
- Attributes:
  - `TownId` (string)
  - `Type` (string) — example: `Tavern`, `Fountain`, `Market` (you can add your own)
  - `Capacity` (number, optional)
  - `Radius` (number, optional)

NPCs can form a little circle here, face in, and talk. :contentReference[oaicite:5]{index=5}

**SpawnGate**
- Tag: `SpawnGate`
- Attributes:
  - `TownId` (string)
  - `Weight` (number, optional) — higher = used more
  - `Node` (string, optional) — name of the RoadNode it connects to (if not set, it picks the nearest node)

NPCs “walk in” from gates, and later walk back out and vanish, then come back later. :contentReference[oaicite:6]{index=6}

---

## Bubble talk (TextChatService)

Meetup talk uses Roblox bubble chat (`TextChatService:DisplayBubble`). :contentReference[oaicite:7]{index=7}

To see bubbles:
- Make sure Bubble Chat is enabled in your experience settings (or set `AutoEnableBubbleChat = true` in `Config.lua`). :contentReference[oaicite:8]{index=8}

---

## Where to tweak stuff

### `ReplicatedStorage/TownLife/Config.lua`
This is where you change:
- how many NPCs exist per town
- how many can be visible at once
- how far away they show up
- walking speed + how often they update
- meetup sizes / frequency
- dialogue frequency
- spawn gate timing (how long before they leave, how long before they come back) :contentReference[oaicite:9]{index=9}

### `ReplicatedStorage/TownLife/Dialogue.lua`
Dialogue is just lists of lines grouped by hotspot type (`PACKS` table). Add your own types and lines there. :contentReference[oaicite:10]{index=10}

---

## Notes

- This is **ambient**. It’s meant to look like a town is alive, not be a deep “real” sim.
- It runs on the **client**, so different players can see different crowds (that’s intentional for performance). :contentReference[oaicite:11]{index=11}
- NPCs are simple R6-shaped part models (no Humanoid). :contentReference[oaicite:12]{index=12}