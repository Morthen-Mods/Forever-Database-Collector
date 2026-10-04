-- Forever-Database-Collector/Quests.lua
-- Quest texts, quest givers and turn-ins, rewards, objectives and who was able
-- to accept a quest. Provides the data for quests, quest_texts, quest_npcs,
-- quest_objects, quest_rewards and quest_objectives.
local _, ns = ...

local Safe, SafeBool = ns.Safe, ns.SafeBool

-- Enum.QuestTag -> values of the quest_tag enum in the schema
local QUEST_TAGS = { [1] = "Group", [41] = "PvP", [62] = "Raid", [81] = "Dungeon", [83] = "Legendary" }

local function CurrentQuestID()
    local questID = Safe(GetQuestID(), "quest.id")
    if not questID or questID == 0 then return nil end
    return questID
end

-- Records who gives or takes the quest in the open quest window
local function RecordGiver(questID, role)
    local kind, id = ns.RecordUnit("npc", true)
    if kind == "npc" then
        ns.AddUnique("quest_npcs", questID .. ":" .. id .. ":" .. role,
            { quest_id = questID, npc_id = id, role = role })
    elseif kind == "object" then
        ns.AddUnique("quest_objects", questID .. ":" .. id .. ":" .. role,
            { quest_id = questID, object_id = id, role = role })
    end
end

-- Items from the quest window: "reward", "choice" or "required"
local function ReadQuestItems(itemType, count)
    local list = {}
    for index = 1, Safe(count, "quest.items.count") or 0 do
        local itemID = ns.ItemIDFromLink(GetQuestItemLink(itemType, index), "quest.items.link")
        if itemID then
            local _, _, numItems = GetQuestItemInfo(itemType, index)
            table.insert(list, { item_id = itemID, count = Safe(numItems, "quest.items.count") or 1 })
            ns.RecordItem(itemID)
        end
    end
    return list
end

local function RecordRewards(quest)
    quest.rewards = ReadQuestItems("reward", GetNumQuestRewards())
    quest.choices = ReadQuestItems("choice", GetNumQuestChoices())
    ns.Merge(quest, { reward_money = GetRewardMoney() }, "quest")
end

-- ---------------------------------------------------------------------------
-- Quest window
-- ---------------------------------------------------------------------------

ns:RegisterEvent("QUEST_DETAIL", function(questStartItemID)
    local questID = CurrentQuestID()
    if not questID then return end

    local quest = ns.GetEntry("quests", questID)
    ns.Merge(quest, {
        title = GetTitleText(),
        details = GetQuestText(),
        objectives = GetObjectiveText(),
    }, "quest")
    RecordRewards(quest)

    questStartItemID = Safe(questStartItemID, "quest.start_item")
    if questStartItemID and questStartItemID > 0 then
        ns.AddUnique("quest_items", questID .. ":" .. questStartItemID,
            { quest_id = questID, item_id = questStartItemID, role = "start" })
        ns.RecordItem(questStartItemID)
    else
        RecordGiver(questID, "start")
    end
end)

ns:RegisterEvent("QUEST_PROGRESS", function()
    local questID = CurrentQuestID()
    if not questID then return end

    local quest = ns.GetEntry("quests", questID)
    ns.Merge(quest, { title = GetTitleText(), request_text = GetProgressText() }, "quest")
    local required = ReadQuestItems("required", GetNumQuestItems())
    if #required > 0 then quest.required_items = required end
    RecordGiver(questID, "end")
end)

ns:RegisterEvent("QUEST_COMPLETE", function()
    local questID = CurrentQuestID()
    if not questID then return end

    local quest = ns.GetEntry("quests", questID)
    ns.Merge(quest, { title = GetTitleText(), completion_text = GetRewardText() }, "quest")
    RecordRewards(quest)
    RecordGiver(questID, "end")
end)

ns:RegisterEvent("QUEST_TURNED_IN", function(questID, xpReward, moneyReward)
    questID = Safe(questID, "quest.turned_in")
    if not questID then return end
    ns.Merge(ns.GetEntry("quests", questID),
        { reward_xp = xpReward, reward_money_observed = moneyReward }, "quest")
end)

-- ---------------------------------------------------------------------------
-- Quest log: data that is only available after accepting
-- ---------------------------------------------------------------------------

local function GetLogInfo(logIndex)
    return Safe(C_QuestLog.GetInfo(logIndex), "questlog.info")
end

-- The header above the quest is the zone or category name (ZoneOrSort)
local function GetLogHeader(logIndex)
    for index = logIndex - 1, 1, -1 do
        local info = GetLogInfo(index)
        if info and SafeBool(info.isHeader, "questlog.header") then
            return Safe(info.title, "questlog.header_title")
        end
    end
end

local function GetObjectives(questID)
    return Safe(C_QuestLog.GetQuestObjectives(questID), "quest.objectives")
end

-- Objective texts without progress ("0/8 Juvenile Vuldren slain" -> "Juvenile Vuldren slain").
-- Right after accepting the names are often missing, so they are read again later.
local function RecordObjectives(questID)
    local objectives = GetObjectives(questID)
    if not objectives or #objectives == 0 then return end
    local list = {}
    for index, objective in ipairs(objectives) do
        local text = Safe(objective.text, "quest.objective.text")
        if type(text) == "string" then
            text = text:gsub("^%d+/%d+%s*", ""):gsub("%s+", " ")
        end
        table.insert(list, {
            index = index,
            type = Safe(objective.type, "quest.objective.type"),   -- monster, item, object, event, reputation, log …
            text = text,
            count = Safe(objective.numRequired, "quest.objective.count"),
        })
    end
    ns.GetEntry("quests", questID).objective_list = list
end

ns:RegisterEvent("QUEST_ACCEPTED", function(questID)
    questID = Safe(questID, "quest.accepted")
    if not questID then return end

    local quest = ns.GetEntry("quests", questID)
    local logIndex = Safe(C_QuestLog.GetLogIndexForQuestID(questID), "questlog.index")
    local info = logIndex and GetLogInfo(logIndex)
    local tagInfo = Safe(C_QuestLog.GetQuestTagInfo(questID), "quest.tag")
    local tagID = tagInfo and Safe(tagInfo.tagID, "quest.tag.id")

    ns.Merge(quest, {
        title = info and info.title,
        level = info and info.level,
        suggested_group = info and info.suggestedGroup,
        frequency = info and info.frequency,
        is_auto_complete = info and info.isAutoComplete,
        log_header = logIndex and GetLogHeader(logIndex),
        is_repeatable = C_QuestLog.IsRepeatableQuest(questID),
        tag = tagID and QUEST_TAGS[tagID],
        tag_id = tagID,
        is_elite = tagInfo and tagInfo.isElite,
    }, "quest")
    RecordObjectives(questID)

    -- Who was able to accept the quest -> required_races / required_classes / side
    local _, race = UnitRace("player")
    local _, class = UnitClass("player")
    race, class = Safe(race, "player.race"), Safe(class, "player.class")
    if race and class then
        ns.AddUnique("quest_accepts", questID .. ":" .. race .. ":" .. class, {
            quest_id = questID,
            race = race,
            class = class,
            faction = Safe(UnitFactionGroup("player"), "player.faction"),
            level = Safe(UnitLevel("player"), "player.level"),
        })
    end
end)

-- ---------------------------------------------------------------------------
-- Kill objectives: which NPC counts for which objective?
-- ---------------------------------------------------------------------------

local progress = {}  -- [questID] = { [index] = numFulfilled } (state before the progress)
local changed = {}   -- [questID] = npcID of the suspected trigger, or false
local lastHostile    -- { id, time }: last targeted hostile NPC

-- When targeting (usually before the pull, i.e. out of combat) the GUID is
-- reliably readable; in combat the client may block it
ns:RegisterEvent("PLAYER_TARGET_CHANGED", function()
    if not SafeBool(UnitCanAttack("player", "target"), "kill.can_attack") then return end
    local kind, id = ns.UnitID("target", "kill.target_guid")
    if kind == "npc" then lastHostile = { id = id, time = GetTime() } end
end)

-- Returns the NPC and where the attribution came from (for the statistics)
local function GetKillCandidate()
    if SafeBool(UnitExists("target"), "kill.target_exists")
        and SafeBool(UnitIsDead("target"), "kill.target_dead") then
        local kind, id = ns.UnitID("target", "kill.dead_guid")
        if kind == "npc" then return id, "dead_target" end
    end
    if lastHostile and GetTime() - lastHostile.time < 30 then return lastHostile.id, "last_hostile" end
    return false, "none"
end

local function Snapshot(questID)
    local objectives = GetObjectives(questID)
    if not objectives then return nil end
    local counts = {}
    for index, objective in ipairs(objectives) do
        counts[index] = Safe(objective.numFulfilled, "kill.fulfilled")
    end
    return counts, objectives
end

-- Baseline of all quests in the log
local function SnapshotLog()
    for index = 1, Safe(C_QuestLog.GetNumQuestLogEntries(), "questlog.count") or 0 do
        local questID = Safe(C_QuestLog.GetQuestIDForLogIndex(index), "questlog.quest_id")
        if questID then progress[questID] = Snapshot(questID) end
    end
end

ns:RegisterEvent("PLAYER_ENTERING_WORLD", SnapshotLog)
ns:RegisterEvent("QUEST_ACCEPTED", function(questID)
    questID = Safe(questID, "quest.accepted")
    if not questID then return end
    progress[questID] = Snapshot(questID)
    changed[questID] = false    -- re-read the objective texts on the next log update
end)

-- Fires when a quest objective progresses
ns:RegisterEvent("QUEST_WATCH_UPDATE", function(questID)
    questID = Safe(questID, "kill.watch_quest")
    if not questID then return end
    local npcID, source = GetKillCandidate()
    ns:CountStat("kill.watch." .. source)
    changed[questID] = npcID
end)

ns:RegisterEvent("QUEST_LOG_UPDATE", function()
    for questID, npcID in pairs(changed) do
        local before = progress[questID]
        local after, objectives = Snapshot(questID)
        RecordObjectives(questID)
        if npcID and before and after then
            for index, objective in ipairs(objectives) do
                local isMonster = Safe(objective.type, "kill.objective_type") == "monster"
                if isMonster and (after[index] or 0) > (before[index] or 0) then
                    ns.AddUnique("quest_objective_kills", questID .. ":" .. index .. ":" .. npcID,
                        { quest_id = questID, index = index, npc_id = npcID })
                    ns:CountStat("kill.recorded")
                end
            end
        end
        progress[questID] = after
        changed[questID] = nil
    end
end)

ns:RegisterEvent("QUEST_REMOVED", function(questID)
    questID = Safe(questID, "quest.removed")
    if not questID then return end
    progress[questID] = nil
    changed[questID] = nil
end)
