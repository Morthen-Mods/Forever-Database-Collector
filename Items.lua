-- Forever-Database-Collector/Items.lua
-- Stores the base data of every item that shows up anywhere (loot, quest
-- rewards, vendors). Items the client has not loaded yet are requested.
-- Tooltip data (stats, damage, effects, sets …) comes from
-- Forever-Item-Scraper, which reads every item of the client.
local _, ns = ...

-- Enum.ItemQuality -> values of the item_quality enum in the schema
local QUALITY = {
    [0] = "Poor", [1] = "Common", [2] = "Uncommon", [3] = "Rare",
    [4] = "Epic", [5] = "Legendary", [6] = "Artifact",
}

-- bindType of C_Item.GetItemInfo -> item_bonding enum ("none" = does not bind)
local BONDING = { [0] = "none", [1] = "pickup", [2] = "equip", [3] = "use", [4] = "quest" }

local done = {}
local waiting = {}

local function StoreItem(itemID)
    local name, _, quality, itemLevel, minLevel, _, _, maxStack, equipLoc, icon,
        sellPrice, classID, subclassID, bindType, _, _, _, description = C_Item.GetItemInfo(itemID)
    if not ns.Safe(name, "item.name") then return false end

    quality = ns.Safe(quality, "item.quality")
    bindType = ns.Safe(bindType, "item.bonding")
    ns.Merge(ns.GetEntry("items", itemID), {
        name = name,
        description = description,
        quality = quality and QUALITY[quality],
        item_level = itemLevel,
        required_level = minLevel,
        class_id = classID,
        subclass_id = subclassID,
        inventory_type = equipLoc,      -- e.g. "INVTYPE_HEAD", the website converts it
        icon = icon,                    -- FileDataID
        sell_price = sellPrice,
        max_stack = maxStack,
        bonding = bindType and BONDING[bindType],
    }, "item")
    done[itemID] = true
    return true
end

function ns.RecordItem(itemID)
    itemID = ns.Safe(itemID, "item.id")
    if not itemID or done[itemID] or waiting[itemID] then return end
    if not StoreItem(itemID) then
        waiting[itemID] = true
        C_Item.RequestLoadItemDataByID(itemID)
    end
end

ns:RegisterEvent("ITEM_DATA_LOAD_RESULT", function(itemID, success)
    if not waiting[itemID] then return end
    waiting[itemID] = nil
    if success then StoreItem(itemID) end
end)
