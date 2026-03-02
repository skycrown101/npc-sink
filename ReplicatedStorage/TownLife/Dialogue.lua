local TextChatService = game:GetService("TextChatService")
local Lighting = game:GetService("Lighting")

local Dialogue = {}

local function randRange(rng, a, b)
	return a + (b - a) * rng:NextNumber()
end

local function dayPart()
	-- Uses project time if they have one; works with your own time too.
	local t = Lighting.ClockTime
	if t >= 5 and t < 10 then return "morning", "this morning" end
	if t >= 10 and t < 17 then return "day", "today" end
	if t >= 17 and t < 21 then return "evening", "tonight" end
	return "night", "tonight"
end

local function fmt(line, ctx)
	-- tiny templating
	line = line:gsub("{when}", ctx.when)
	line = line:gsub("{place}", ctx.place)
	return line
end

-- Contextual packs by hotspot type
local PACKS = {
	Generic = {
		place = "around here",
		lines = {
			"Feels like {place} has been quieter {when}.",
			"I don’t trust the way the wind changed {when}.",
			"Someone’s been asking questions {when}.",
			"Keep it between us, alright?",
			"I swear I saw lights over the roofs {when}.",
		},
		reactions = {"Yeah.", "No way.", "Huh.", "True.", "…maybe.", "If you say so."},
	},
	Tavern = {
		place = "the tavern",
		lines = {
			"Last call is never really last call in {place}.",
			"Did you hear what happened {when}?",
			"Don’t play cards with the one in the corner.",
			"If you’re looking for trouble, {place} delivers.",
			"They say the cellar door opens by itself {when}.",
		},
		reactions = {"Cheers.", "That’s wild.", "I’m not buying it.", "Keep going.", "Shh."},
	},
	Fountain = {
		place = "the fountain",
		lines = {
			"Make a wish at {place} and don’t look back.",
			"The water’s colder {when}. That’s a bad sign.",
			"I saw a coin float upstream here once.",
			"Meet here later. Same spot.",
			"Listen… you can almost hear it talking {when}.",
		},
		reactions = {"Creepy.", "I felt that too.", "Don’t joke.", "Okay—nope.", "Interesting."},
	},
	Market = {
		place = "the market",
		lines = {
			"Prices doubled since {when}.",
			"Don’t buy fruit from the red stall.",
			"There’s a rumor a caravan vanished {when}.",
			"Someone’s selling “lucky charms” again.",
			"Keep your purse close in {place}.",
		},
		reactions = {"I knew it.", "Scam.", "That tracks.", "Unlucky.", "Say less."},
	},
}

local function getPack(hotspotType)
	return PACKS[hotspotType] or PACKS.Generic
end

function Dialogue.EnsureBubbleChat(config)
	if config.AutoEnableBubbleChat then
		local cfg = TextChatService:FindFirstChild("BubbleChatConfiguration")
		if cfg then cfg.Enabled = true end
	end
end

local function displayBubble(config, model, text)
	local adornee = model:FindFirstChild(config.DialogueAdorneePartName) or model.PrimaryPart
	if not adornee then return end
	pcall(function()
		TextChatService:DisplayBubble(adornee, text)
	end)
end

local function pickOtherParticipant(rng, participants, speakerId)
	if #participants <= 1 then return nil end
	for _ = 1, 4 do
		local id = participants[rng:NextInteger(1, #participants)]
		if id ~= speakerId then
			return id
		end
	end
	-- fallback: first that isn't speaker
	for _, id in ipairs(participants) do
		if id ~= speakerId then return id end
	end
	return nil
end

function Dialogue.StepTown(town, config, renderer, now)
	if not config.DialogueEnabled or not config.MeetupTalkEnabled then return end
	if not town._events then return end

	local part, when = dayPart()

	for _, ev in ipairs(town._events) do
		if ev.type ~= "Meetup" then
			continue
		end

		-- Flush queued reactions
		if ev.pending and #ev.pending > 0 then
			for i = #ev.pending, 1, -1 do
				local item = ev.pending[i]
				if now >= item.at then
					local m = renderer.active[item.id]
					if m then
						displayBubble(config, m, item.text)
					end
					table.remove(ev.pending, i)
				end
			end
		end

		-- Speaker line
		if (ev.linesLeft or 0) > 0 and now >= (ev.nextLineAt or 0) then
			local speakerModel = renderer.active[ev.speakerId]
			if not speakerModel then
				-- speaker not currently rendered; try again soon
				ev.nextLineAt = now + 1.0
				continue
			end

			local hsType = (ev.hotspot and ev.hotspot.type) or "Generic"
			local pack = getPack(hsType)

			local ctx = {
				when = when,
				place = pack.place,
			}

			local line = pack.lines[town.rng:NextInteger(1, #pack.lines)]
			displayBubble(config, speakerModel, fmt(line, ctx))

			ev.linesLeft -= 1
			ev.nextLineAt = now + randRange(town.rng, config.MeetupSpeakerLineIntervalRange[1], config.MeetupSpeakerLineIntervalRange[2])

			-- Maybe schedule a listener reaction
			if town.rng:NextNumber() < config.MeetupReactionChance then
				local responderId = pickOtherParticipant(town.rng, ev.participants, ev.speakerId)
				if responderId then
					local reaction = pack.reactions[town.rng:NextInteger(1, #pack.reactions)]
					table.insert(ev.pending, {
						id = responderId,
						at = now + randRange(town.rng, config.MeetupReactionDelayRange[1], config.MeetupReactionDelayRange[2]),
						text = reaction,
					})
				end
			end
		end
	end
end

return Dialogue
