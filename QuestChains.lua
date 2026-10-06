-- Forever-Database-Collector/QuestChains.lua
-- Questlines. The client does not say which quest a quest requires, so this is
-- mostly guesswork: every accepted quest is stored together with the quests
-- turned in shortly before it, plus the clues for and against a real link.
-- A quest that the same NPC offers right after a turn-in (and did not offer
-- before) is marked strong_hint, so it can be checked by hand first.
-- The website only trusts a link that many observations agree on.
-- Where the client knows a questline (C_QuestLine), it is stored directly.
local _, ns = ...

local Safe = ns.Safe

local WINDOW = 600      -- seconds: turn-ins older than this are no candidates
local CANDIDATES = 3    -- at most this many previous turn-ins per accepted quest
local TOLERANCE = 3     -- seconds: events this close count as "at the same time"
local AFTER = 60        -- seconds: an NPC window this soon after a turn-in counts as "right after"

-- Session state only; it belongs to the logged-in character
local turnIns = {}      -- newest last: { quest_id, at, giver, gossip }
local details = {}      -- [questID] = { at, giver, gossip } of the last quest window
local seenAvailable = {} -- [questID] = GetTime() of the first sighting as available
local gossip = 0        -- counts opened gossip/greeting windows
local completeGiver     -- { quest_id, giver } of the open reward window
local hints = {}        -- [questID:prevID] = entry in quest_chain_hints, to add clues later

-- "npc:123" / "object:45" of the unit in the quest window
local function CurrentGiver()
    local kind, id = ns.UnitID("npc", "chain.giver")
    return kind and (kind .. ":" .. id) or nil
end

-- ---------------------------------------------------------------------------
-- Questlines known to the client
-- ---------------------------------------------------------------------------

local function RecordQuestLine(questID)
    if not C_QuestLine then return end
    local uiMapID = Safe(C_Map.GetBestMapForUnit("player"), "questline.map")
    local info = Safe(C_QuestLine.GetQuestLineInfo(questID, uiMapID), "questline.info")
    local lineID = info and Safe(info.questLineID, "questline.id")
    if not lineID or lineID == 0 then return end

    ns.GetEntry("quests", questID).quest_line_id = lineID
    local line = ns.Merge(ns.GetEntry("quest_lines", lineID), { name = info.questLineName }, "questline")
    local quests = Safe(C_QuestLine.GetQuestLineQuests(lineID), "questline.quests")
    if type(quests) == "table" and #quests > 0 then
        local list = {}
        for _, id in ipairs(quests) do
            id = Safe(id, "questline.quest")
            if id then table.insert(list, id) end
        end
        line.quests = list     -- in the client's order
    end
    ns:CountStat("questline.known")
end

-- ---------------------------------------------------------------------------
-- Clues
-- ---------------------------------------------------------------------------

-- One entry per quest pair; later clues are added to the same entry
local function Hint(questID, prevID)
    local key = questID .. ":" .. prevID
    if not hints[key] then
        local entry = {
            quest_id = questID, prev_quest_id = prevID,
            strong_hint = false, offered = false, listed_after = false, accepted = false,
        }
        -- Already stored before a /reload: the new clues are dropped
        if not ns.AddUnique("quest_chain_hints", key, entry) then entry = {} end
        hints[key] = entry
    end
    return hints[key]
end

-- Not offered anywhere before the turn-in
local function NewlyAvailable(questID, turnIn)
    local seen = seenAvailable[questID]
    return seen == nil or seen >= turnIn.at - TOLERANCE
end

local function MarkStrong(questID, turnIn, clue)
    if turnIn.quest_id == questID or not NewlyAvailable(questID, turnIn) then return end
    local hint = Hint(questID, turnIn.quest_id)
    if not hint[clue] then ns:CountStat("chain." .. clue) end
    hint[clue] = true
    hint.strong_hint = true
end

-- The latest turn-in, if it was at this giver and only just now
local function TurnInJustNow(giver, seconds)
    local turnIn = turnIns[#turnIns]
    if not turnIn or not giver or turnIn.giver ~= giver then return nil end
    if GetTime() - turnIn.at > seconds then return nil end
    return turnIn
end

-- ---------------------------------------------------------------------------
-- Quests offered by an NPC (to tell "became available" from "was there before")
-- ---------------------------------------------------------------------------

local function SeeAvailable(questID)
    if questID and not seenAvailable[questID] then seenAvailable[questID] = GetTime() end
end

-- Quests listed in a gossip/greeting window
local function SeeOffers(questIDs)
    gossip = gossip + 1
    local turnIn = TurnInJustNow(CurrentGiver(), AFTER)
    for _, questID in ipairs(questIDs) do
        if turnIn then MarkStrong(questID, turnIn, "listed_after") end
        SeeAvailable(questID)
    end
end

ns:RegisterEvent("GOSSIP_SHOW", function()
    local questIDs = {}
    for _, info in ipairs(Safe(C_GossipInfo.GetAvailableQuests(), "chain.gossip") or {}) do
        table.insert(questIDs, Safe(info.questID, "chain.available"))
    end
    SeeOffers(questIDs)
end)

ns:RegisterEvent("QUEST_GREETING", function()
    local questIDs = {}
    if GetNumAvailableQuests and GetAvailableQuestInfo then
        for index = 1, Safe(GetNumAvailableQuests(), "chain.greeting.count") or 0 do
            table.insert(questIDs, Safe(select(5, GetAvailableQuestInfo(index)), "chain.available"))
        end
    end
    SeeOffers(questIDs)
end)

-- ---------------------------------------------------------------------------
-- Turn-in -> accept
-- ---------------------------------------------------------------------------

ns:RegisterEvent("QUEST_DETAIL", function()
    local questID = Safe(GetQuestID(), "chain.detail")
    if not questID or questID == 0 then return end
    local giver = CurrentGiver()
    details[questID] = { at = GetTime(), giver = giver, gossip = gossip }

    -- Shown by the game right after the turn-in, without the player opening
    -- the NPC again: the follow-up quest
    local turnIn = TurnInJustNow(giver, TOLERANCE)
    if turnIn and turnIn.gossip == gossip then MarkStrong(questID, turnIn, "offered") end

    SeeAvailable(questID)
    RecordQuestLine(questID)
end)

ns:RegisterEvent("QUEST_COMPLETE", function()
    local questID = Safe(GetQuestID(), "chain.complete")
    if questID then completeGiver = { quest_id = questID, giver = CurrentGiver() } end
end)

ns:RegisterEvent("QUEST_TURNED_IN", function(questID)
    questID = Safe(questID, "chain.turned_in")
    if not questID then return end
    local giver = completeGiver and completeGiver.quest_id == questID and completeGiver.giver or CurrentGiver()
    completeGiver = nil

    table.insert(turnIns, { quest_id = questID, at = GetTime(), giver = giver, gossip = gossip })
    while #turnIns > 10 do table.remove(turnIns, 1) end

    -- The follow-up window can open before the turn-in event arrives
    local turnIn = turnIns[#turnIns]
    for detailID, detail in pairs(details) do
        if giver and detail.giver == giver and detail.gossip == gossip
            and math.abs(detail.at - turnIn.at) <= TOLERANCE then
            MarkStrong(detailID, turnIn, "offered")
        end
    end
end)

ns:RegisterEvent("QUEST_ACCEPTED", function(questID)
    questID = Safe(questID, "chain.accepted")
    if not questID then return end
    local now = GetTime()
    local detail = details[questID]
    local giver = detail and detail.giver
    local seen = seenAvailable[questID]
    details[questID] = nil

    local rank = 0
    for i = #turnIns, 1, -1 do
        local t = turnIns[i]
        if now - t.at > WINDOW or rank >= CANDIDATES then break end
        if t.quest_id ~= questID then
            rank = rank + 1
            local hint = Hint(questID, t.quest_id)
            hint.accepted = true
            hint.rank = rank                                    -- 1 = last turn-in before accepting
            hint.seconds = math.floor(now - t.at)
            hint.same_giver = giver ~= nil and giver == t.giver
            -- Already offered before the turn-in: then it is no prerequisite
            hint.seen_before = seen ~= nil and seen < t.at - TOLERANCE
        end
    end
    ns:CountStat(rank > 0 and "chain.hint" or "chain.no_candidate")

    RecordQuestLine(questID)
end)
