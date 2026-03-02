-- ReplicatedStorage/TownLife/Dialogue.lua
local TextChatService = game:GetService("TextChatService")

local Dialogue = {}

local LINES = {
	"…so I told him, no way.",
	"Did you hear the bells last night?",
	"This town feels different today.",
	"Keep your voice down.",
	"I could eat an entire wagon of bread.",
	"Somebody’s watching us.",
	"Meet me by the fountain later.",
	"I swear I saw lights in the sky.",
	"Have you been to the market recently?",
	"Long day. Longer night.",
}

local function randRange(rng, a, b)
	return a + (b - a) * rng:NextNumber()
end

function Dialogue.EnsureBubbleChat(config)
	-- Optional: don’t override project settings unless you want it to “just work”
	if config.AutoEnableBubbleChat then
		local cfg = TextChatService:FindFirstChild("BubbleChatConfiguration")
		if cfg then
			cfg.Enabled = true
		end
	end
end

function Dialogue.TrySpeak(config, townRng, model, text)
	if not config.DialogueEnabled then return end
	if not model then return end

	local adornee = model:FindFirstChild(config.DialogueAdorneePartName) or model.PrimaryPart
	if not adornee then return end

	-- DisplayBubble is client-side; wrap in pcall to avoid hard errors
	pcall(function()
		TextChatService:DisplayBubble(adornee, text)
	end)
end

function Dialogue.MaybeSpeak(config, townRng, agent, model, now)
	if not config.DialogueEnabled then return end

	-- Only talk during meetups (cheap + looks intentional)
	if config.DialogueMeetupOnly and agent.state ~= "MeetupIdle" then
		return
	end

	if now < (agent.nextTalkAt or 0) then
		return
	end

	-- Chance gate so everyone doesn’t talk at once
	if townRng:NextNumber() > config.DialogueTalkChance then
		agent.nextTalkAt = now + randRange(townRng, config.DialogueTalkIntervalRange[1], config.DialogueTalkIntervalRange[2])
		return
	end

	local line = LINES[townRng:NextInteger(1, #LINES)]
	Dialogue.TrySpeak(config, townRng, model, line)

	agent.nextTalkAt = now + randRange(townRng, config.DialogueTalkIntervalRange[1], config.DialogueTalkIntervalRange[2])
end

return Dialogue
