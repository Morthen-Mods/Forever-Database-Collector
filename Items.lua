-- Forever-Database-Collector/Items.lua
-- Stores every item that shows up anywhere (loot, quest rewards, vendors):
-- the data of GetItemInfo and the tooltip values (ItemTooltip.lua), in the
-- item format of Forever-Item-Scraper. Items the client has not loaded yet
-- are requested.
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
    local name, link, quality, itemLevel, minLevel, className, subclassName, maxStack, equipLoc, icon,
        sellPrice, classID, subclassID, bindType, expansionID, setID, craftingReagent, description = C_Item.GetItemInfo(itemID)
    if not ns.Safe(name, "item.name") then return false end

    quality = ns.Safe(quality, "item.quality")
    bindType = ns.Safe(bindType, "item.bonding")
    local entry = ns.Merge(ns.GetEntry("items", itemID), {
        name = name,
        description = description,
        quality = quality and QUALITY[quality],
        item_level = itemLevel,
        required_level = minLevel,
        class_id = classID,
        subclass_id = subclassID,
        class_name = className,         -- localized, e.g. "Rüstung"
        subclass_name = subclassName,   -- localized, e.g. "Platte"
        inventory_type = equipLoc,      -- e.g. "INVTYPE_HEAD", the website converts it
        icon = icon,                    -- FileDataID
        sell_price = sellPrice,
        max_stack = maxStack,
        bonding = bindType and BONDING[bindType],
        expansion_id = expansionID,
        crafting_reagent = craftingReagent,
        set_id = setID,
        bag_family = C_Item.GetItemFamily(itemID),  -- bit field of bag types
    }, "item")

    -- A tooltip the addon cannot read must not stop the base data. Its values
    -- are copied as they are: "" and empty lists mean "no such line".
    local ok, tooltip, set = pcall(ns.ReadTooltip, itemID, ns.Safe(link, "item.link"), entry)
    if not ok then
        ns:LogError("item.tooltip", tooltip)
    elseif tooltip then
        for key, value in pairs(tooltip) do entry[key] = value end
    end

    -- Every member shows the whole set; a set block read from the tooltip
    -- (it has a size) beats a bare name and is never replaced by one
    if entry.set_id then
        local sets = ns.db.pending.sets
        local key = tostring(entry.set_id)
        if ok and set and set.size then
            sets[key] = set
        elseif not sets[key] then
            local setName = (ok and set and set.name) or ns.Safe(C_Item.GetItemSetInfo(entry.set_id), "item.set.name")
            if setName and setName ~= "" then sets[key] = { name = setName } end
        end
    end

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
