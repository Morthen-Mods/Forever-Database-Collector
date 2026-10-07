-- Forever-Database-Collector/Loot.lua
-- Every opened loot (corpse, chest, herb, ore) is stored once per GUID as an
-- observation. The website derives npc_loot.chance from it
-- (number of drops ÷ number of opened loots of that NPC).
local _, ns = ...

local Safe, SafeBool = ns.Safe, ns.SafeBool

local lootedGUIDs = {}

ns:RegisterEvent("LOOT_OPENED", function()
    if SafeBool(IsFishingLoot(), "loot.fishing") then return end

    -- Blizzard's own UI does not use GetLootSourceInfo; if the client lacks it,
    -- the dead target is used as the source instead (objects are lost then)
    local fallbackGUID = SafeBool(UnitIsDead("target"), "loot.target_dead")
        and Safe(UnitGUID("target"), "loot.target_guid") or nil

    -- Group by source: area loot can show several corpses in one window
    local sources = {}   -- [guid] = { [itemID] = count }
    for slot = 1, Safe(GetNumLootItems(), "loot.count") or 0 do
        local itemID = ns.ItemIDFromLink(GetLootSlotLink(slot), "loot.link")
        local sourceInfo = GetLootSourceInfo and { GetLootSourceInfo(slot) } or { fallbackGUID, 1 }
        for i = 1, #sourceInfo, 2 do
            local guid = Safe(sourceInfo[i], "loot.source_guid")
            local quantity = Safe(sourceInfo[i + 1], "loot.quantity")
            if type(guid) == "string" then
                sources[guid] = sources[guid] or {}
                if itemID then
                    sources[guid][itemID] = (sources[guid][itemID] or 0) + (quantity or 1)
                end
            end
        end
        if itemID then ns.RecordItem(itemID) end
    end

    local uiMapID = Safe(C_Map.GetBestMapForUnit("player"), "loot.map")
    for guid, itemCounts in pairs(sources) do
        local kind, id = ns.ParseGUID(guid)
        if kind and not lootedGUIDs[guid] then
            lootedGUIDs[guid] = true

            local items = {}
            for itemID, count in pairs(itemCounts) do
                table.insert(items, { item_id = itemID, count = count })
            end

            -- Loot without items (money only) still counts toward the drop chance
            if kind == "npc" then
                table.insert(ns.db.pending.npc_loot, { npc_id = id, ui_map_id = uiMapID, items = items })
            else
                table.insert(ns.db.pending.object_loot, { object_id = id, ui_map_id = uiMapID, items = items })
                ns.GetEntry("objects", id)  -- the name comes from the soft target (Units.lua) or the website
                ns.lastObject = { id = id, time = GetTime() }  -- for object objectives (Quests.lua)
                -- For objects the player stands right in front of it -> usable spawn point
                ns.RecordObjectSpawn(id, guid)
            end
        end
    end
end)
