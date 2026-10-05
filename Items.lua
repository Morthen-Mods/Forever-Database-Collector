-- Forever-Database-Collector/Items.lua
-- Stores the base data of every item that shows up anywhere (loot, quest
-- rewards, vendors). Items the client has not loaded yet are requested.
local _, ns = ...

local Safe = ns.Safe

-- Enum.ItemQuality -> values of the item_quality enum in the schema
local QUALITY = {
    [0] = "Poor", [1] = "Common", [2] = "Uncommon", [3] = "Rare",
    [4] = "Epic", [5] = "Legendary", [6] = "Artifact",
}

-- bindType of C_Item.GetItemInfo -> item_bonding enum ("none" = does not bind)
local BONDING = { [0] = "none", [1] = "pickup", [2] = "equip", [3] = "use", [4] = "quest" }

-- C_Item.GetItemStats keys -> item_stat enum
local STATS = {
    ITEM_MOD_STRENGTH_SHORT = "strength",
    ITEM_MOD_AGILITY_SHORT = "agility",
    ITEM_MOD_STAMINA_SHORT = "stamina",
    ITEM_MOD_INTELLECT_SHORT = "intellect",
    ITEM_MOD_SPIRIT_SHORT = "spirit",
    ITEM_MOD_HEALTH_SHORT = "health",
    ITEM_MOD_MANA_SHORT = "mana",
    RESISTANCE1_NAME = "holy_resistance",
    RESISTANCE2_NAME = "fire_resistance",
    RESISTANCE3_NAME = "nature_resistance",
    RESISTANCE4_NAME = "frost_resistance",
    RESISTANCE5_NAME = "shadow_resistance",
    RESISTANCE6_NAME = "arcane_resistance",
}

-- ---------------------------------------------------------------------------
-- Tooltip lines
-- The client's own (localized) templates are turned into patterns, so the
-- tooltip is read the same way in every client language.
-- ---------------------------------------------------------------------------

-- "Durability %d / %d" -> "^Durability (%d+) / (%d+)$"
local function Pattern(template)
    if type(template) ~= "string" then return nil end
    local p = template:gsub("%%%d%$", "%%")                         -- "%1$s" -> "%s"
    p = p:gsub("%%%.?%d*f", "\1"):gsub("%%d", "\2"):gsub("%%s", "\3")
    p = p:gsub("[%(%)%.%+%-%*%?%[%]%^%$%%]", "%%%0")
    p = p:gsub("\1", "([%%d%%.,]+)"):gsub("\2", "(%%d+)"):gsub("\3", "(.-)")
    return "^" .. p .. "$"
end

local function Number(text)
    if type(text) ~= "string" then return nil end
    return tonumber((text:gsub(",", ".")))
end

-- localized school name ("Feuer") -> damage_school enum
local SCHOOLS = {}
for token, global in pairs({
    holy = "STRING_SCHOOL_HOLY", fire = "STRING_SCHOOL_FIRE", nature = "STRING_SCHOOL_NATURE",
    frost = "STRING_SCHOOL_FROST", shadow = "STRING_SCHOOL_SHADOW", arcane = "STRING_SCHOOL_ARCANE",
}) do
    local name = _G[global]
    if type(name) == "string" then SCHOOLS[name:lower()] = token end
end

-- localized class name -> class token ("Krieger" -> "WARRIOR")
local CLASSES = {}
for _, names in ipairs({ LOCALIZED_CLASS_NAMES_MALE or {}, LOCALIZED_CLASS_NAMES_FEMALE or {} }) do
    for token, name in pairs(names) do CLASSES[name] = token end
end

-- Damage lines, the ones with a school first: "%s - %s Damage" would also
-- match "5 - 10 Fire Damage". Captures: min, max (or one value), school.
local DAMAGE = {}
for _, entry in ipairs({
    { "DAMAGE_TEMPLATE_WITH_SCHOOL", "range", true },
    { "PLUS_DAMAGE_TEMPLATE_WITH_SCHOOL", "range", true },
    { "SINGLE_DAMAGE_TEMPLATE_WITH_SCHOOL", "single", true },
    { "DAMAGE_TEMPLATE", "range", false },
    { "PLUS_DAMAGE_TEMPLATE", "range", false },
    { "SINGLE_DAMAGE_TEMPLATE", "single", false },
}) do
    local pattern = Pattern(_G[entry[1]])
    if pattern then tinsert(DAMAGE, { pattern = pattern, kind = entry[2], school = entry[3] }) end
end

local function ParseDamage(text)
    for _, d in ipairs(DAMAGE) do
        local a, b, c = text:match(d.pattern)
        if a then
            local min, max, school
            if d.kind == "range" then
                min, max, school = Number(a), Number(b), c
            else
                min, school = Number(a), b
                max = min
            end
            if d.school then
                school = SCHOOLS[(school or ""):lower()]
            else
                school = "physical"
            end
            if min and max and school then return { school = school, min = min, max = max } end
        end
    end
end

local PATTERNS = {
    durability = Pattern(DURABILITY_TEMPLATE),
    block = Pattern(SHIELD_BLOCK_TEMPLATE),
    bag = Pattern(CONTAINER_SLOTS),
    classes = Pattern(ITEM_CLASSES_ALLOWED),
}

local LINE = Enum.TooltipDataLineType or {}
local TRIGGERS = {
    { type = LINE.ItemSpellTriggerOnUse, prefix = ITEM_SPELL_TRIGGER_ONUSE, trigger = "use" },
    { type = LINE.ItemSpellTriggerOnEquip, prefix = ITEM_SPELL_TRIGGER_ONEQUIP, trigger = "equip" },
    { type = LINE.ItemSpellTriggerOnProc, prefix = ITEM_SPELL_TRIGGER_ONPROC, trigger = "hit" },
}

-- "Equip: Increases …" -> "equip", "Increases …"
local function ParseSpell(text, lineType)
    for _, t in ipairs(TRIGGERS) do
        if type(t.prefix) == "string" and text:sub(1, #t.prefix) == t.prefix then
            return t.trigger, strtrim(text:sub(#t.prefix + 1))
        end
    end
    for _, t in ipairs(TRIGGERS) do
        if t.type and lineType == t.type then return t.trigger, text end
    end
end

local function StripColors(text)
    return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- Everything of the tooltip that GetItemInfo does not return. Numbers are 0
-- and lists empty when the tooltip has no such line, so the website can tell
-- "nothing" from "not read" (older addon versions send none of these fields).
local function ReadTooltip(itemID, link)
    if not C_TooltipInfo then return nil end
    local data = Safe(C_TooltipInfo.GetItemByID(itemID), "item.tooltip")
    local lines = data and Safe(data.lines, "item.tooltip.lines")
    if type(lines) ~= "table" then return nil end

    local values = {
        unique = false, armor = 0, block = 0, durability = 0, weapon_speed = 0, container_slots = 0,
        classes = {}, stats = {}, damage = {}, spells = {},
    }

    local stats = link and Safe(C_Item.GetItemStats(link), "item.stats")
    if type(stats) == "table" then
        for key, value in pairs(stats) do
            if key == "RESISTANCE0_NAME" then
                values.armor = value
            elseif STATS[key] and value ~= 0 then
                values.stats[STATS[key]] = value
            end
        end
    end

    local seenSchools = {}
    for i = 2, #lines do  -- line 1 is the name
        local line = lines[i]
        local left = Safe(line.leftText, "item.tooltip.left")
        if type(left) == "string" and left ~= "" then
            left = StripColors(left)
            local damage = ParseDamage(left)
            local durability = PATTERNS.durability and select(2, left:match(PATTERNS.durability))
            local block = PATTERNS.block and left:match(PATTERNS.block)
            local slots = PATTERNS.bag and left:match(PATTERNS.bag)
            local classes = PATTERNS.classes and left:match(PATTERNS.classes)
            local trigger, spellText = ParseSpell(left, Safe(line.type, "item.tooltip.type"))

            if damage then
                if not seenSchools[damage.school] then
                    seenSchools[damage.school] = true
                    tinsert(values.damage, damage)
                end
                -- the speed stands on the right of the first damage line: "Speed 2.60"
                local right = Safe(line.rightText, "item.tooltip.right")
                local speed = type(right) == "string" and Number(right:match("(%d+[%.,]%d+)"))
                if speed and values.weapon_speed == 0 then values.weapon_speed = math.floor(speed * 1000 + 0.5) end
            elseif left == ITEM_UNIQUE then
                values.unique = true
            elseif durability then
                values.durability = tonumber(durability) or 0
            elseif block then
                values.block = tonumber(block) or 0
            elseif slots then
                values.container_slots = tonumber(slots) or 0
            elseif classes then
                for name in classes:gmatch("[^,]+") do
                    local token = CLASSES[strtrim(name)]
                    if token then tinsert(values.classes, token) end
                end
            elseif trigger and spellText ~= "" then
                tinsert(values.spells, { trigger = trigger, text = spellText })
            end
        end
    end

    -- Only the spell of a "Use:" effect can be read; it belongs to a single use line
    local _, spellID = C_Item.GetItemSpell(itemID)
    spellID = Safe(spellID, "item.spell")
    local useLines = 0
    for _, spell in ipairs(values.spells) do
        if spell.trigger == "use" then useLines = useLines + 1 end
    end
    if spellID and useLines == 1 then
        for _, spell in ipairs(values.spells) do
            if spell.trigger == "use" then spell.spell_id = spellID end
        end
    end
    return values
end

-- ---------------------------------------------------------------------------
-- Items
-- ---------------------------------------------------------------------------

local done = {}
local waiting = {}

local function StoreItem(itemID)
    local name, link, quality, itemLevel, minLevel, _, _, maxStack, equipLoc, icon,
        sellPrice, classID, subclassID, bindType, _, _, _, description = C_Item.GetItemInfo(itemID)
    if not Safe(name, "item.name") then return false end

    quality = Safe(quality, "item.quality")
    bindType = Safe(bindType, "item.bonding")
    local entry = ns.GetEntry("items", itemID)
    ns.Merge(entry, {
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

    -- A tooltip the addon cannot read must not stop the base data
    local ok, tooltip = pcall(ReadTooltip, itemID, Safe(link, "item.link"))
    if not ok then
        ns:LogError("item.tooltip", tooltip)
    elseif tooltip then
        ns.Merge(entry, tooltip, "item")
    end
    done[itemID] = true
    return true
end

function ns.RecordItem(itemID)
    itemID = Safe(itemID, "item.id")
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
