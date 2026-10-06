-- Forever-Database-Collector/ItemTooltip.lua
-- Reads everything of an item tooltip that GetItemInfo does not return:
-- stats with the website's names, armor, damage, speed, effects,
-- requirements, races, the item set … Tooltip lines it cannot place are kept
-- in other_lines, so nothing of the tooltip is lost. Same code and fields as
-- Tooltip.lua of Forever-Item-Scraper; keep both in sync.
local _, ns = ...

-- Secret and empty values are dropped like missing values
local function Safe(value, context)
    value = ns.Safe(value, context)
    if value == "" then return nil end
    return value
end

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
    p = p:gsub("%%%.?%d*[fg]", "\1"):gsub("%%d", "\2"):gsub("%%s", "\3")
    p = p:gsub("[%(%)%.%+%-%*%?%[%]%^%$%%]", "%%%0")
    p = p:gsub("\1", "([%%d%%.,]+)"):gsub("\2", "(%%d+)"):gsub("\3", "(.-)")
    return "^" .. p .. "$"
end

-- "%d |4Charge:Charges;" -> one pattern per plural form
local function PluralPatterns(template)
    if type(template) ~= "string" then return {} end
    local forms = template:match("|4([^;]*);")
    if not forms then return { Pattern(template) } end
    local patterns = {}
    for form in forms:gmatch("[^:]+") do
        tinsert(patterns, Pattern((template:gsub("|4[^;]*;", (form:gsub("%%", "%%%%")), 1))))
    end
    return patterns
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

-- localized race name -> race token ("Nachtelf" -> "NightElf")
local RACES = {}
if C_CreatureInfo and C_CreatureInfo.GetRaceInfo then
    for raceID = 1, 100 do
        local info = C_CreatureInfo.GetRaceInfo(raceID)
        if info and type(info.raceName) == "string" and type(info.clientFileString) == "string" then
            RACES[info.raceName] = info.clientFileString
        end
    end
end

-- localized reputation standing -> standing ID ("Wohlwollend" -> 6)
local STANDINGS = {}
for standing = 1, 8 do
    for _, suffix in ipairs({ "", "_FEMALE" }) do
        local label = _G["FACTION_STANDING_LABEL" .. standing .. suffix]
        if type(label) == "string" then STANDINGS[label] = standing end
    end
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
    races = Pattern(ITEM_RACES_ALLOWED),
    unique_count = Pattern(ITEM_UNIQUE_MULTIPLE),       -- "Unique (20)"
    ammo_dps = Pattern(AMMO_DAMAGE_TEMPLATE),           -- "Adds 2.5 damage per second"
    skill = Pattern(ITEM_MIN_SKILL),                    -- "Requires Tailoring (150)"
    reputation = Pattern(ITEM_REQ_REPUTATION),          -- "Requires Timbermaw Hold - Honored"
    requires = Pattern(ITEM_REQ_SKILL),                 -- "Requires %s", checked after all other "Requires" lines
    set_name = Pattern(ITEM_SET_NAME),                  -- "Battlegear of Might (0/8)"
    set_bonus_count = Pattern(ITEM_SET_BONUS_GRAY),     -- "(3) Set: …"
    set_bonus = Pattern(ITEM_SET_BONUS),                -- "Set: …" (bonus already active)
}

-- Lines that are just a yes/no flag of the item
local FLAGS = {}
for field, global in pairs({
    starts_quest = "ITEM_STARTS_QUEST", openable = "ITEM_OPENABLE", readable = "ITEM_READABLE",
    locked = "LOCKED", conjured = "ITEM_CONJURED", random_enchant = "ITEM_RANDOM_ENCHANT",
    unique_equipped = "ITEM_UNIQUE_EQUIPPABLE",
}) do
    local text = _G[global]
    if type(text) == "string" then FLAGS[text] = field end
end

-- Lines that only repeat what GetItemInfo / GetItemStats already returned
local KNOWN_TEXTS = {}
for _, global in ipairs({
    "ITEM_BIND_ON_PICKUP", "ITEM_BIND_ON_EQUIP", "ITEM_BIND_ON_USE", "ITEM_BIND_QUEST", "ITEM_SOULBOUND",
    "ITEM_BIND_TO_ACCOUNT", "ITEM_BIND_TO_BNETACCOUNT", "ITEM_ACCOUNTBOUND", "ITEM_BNETACCOUNTBOUND",
}) do
    local text = _G[global]
    if type(text) == "string" then KNOWN_TEXTS[text] = true end
end

local KNOWN_PATTERNS = { "^[%+%-]%d+ " }  -- stat lines: "+5 Agility", "-2 Spirit"
for _, global in ipairs({ "ITEM_MIN_LEVEL", "ITEM_LEVEL", "ARMOR_TEMPLATE", "DPS_TEMPLATE" }) do
    local pattern = Pattern(_G[global])
    if pattern then tinsert(KNOWN_PATTERNS, pattern) end
end

local LINE = Enum.TooltipDataLineType or {}
local KNOWN_TYPES = {}
for _, name in ipairs({ "ItemName", "ItemBinding", "EquipSlot", "SellPrice", "ItemLevel", "FlavorText", "Blank", "Separator", "ItemQuality" }) do
    if LINE[name] then KNOWN_TYPES[LINE[name]] = true end
end

local function IsKnownLine(text, lineType, item)
    if KNOWN_TEXTS[text] or KNOWN_TYPES[lineType] then return true end
    if item.description and text == '"' .. item.description .. '"' then return true end
    -- equip slot line: "Head" on the left, the subclass ("Plate") on the right
    if item.inventory_type and text == _G[item.inventory_type] then return true end
    if type(SELL_PRICE) == "string" and text:sub(1, #SELL_PRICE) == SELL_PRICE then return true end
    for _, pattern in ipairs(KNOWN_PATTERNS) do
        if text:match(pattern) then return true end
    end
    return false
end

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

local function Match(pattern, text)
    if pattern then return text:match(pattern) end
end

local CHARGES = PluralPatterns(ITEM_SPELL_CHARGES)    -- "5 Charges"

local function MatchCharges(text)
    for _, pattern in ipairs(CHARGES) do
        local count = text:match(pattern)
        if count then return count end
    end
end

-- The set block of the tooltip: "Name (0/8)", the member names (indented),
-- then the bonuses "(2) Set: …". Returns true when the line belonged to it.
local function ReadSetLine(set, text, state)
    local name, _, size = Match(PATTERNS.set_name, text)
    if name and not set.size then
        set.name = set.name or strtrim(name)
        set.size = tonumber(size)
        state.members = true
        return true
    end
    local count, bonus = Match(PATTERNS.set_bonus_count, text)
    if count then
        state.members = false
        tinsert(set.bonuses, { count = tonumber(count), text = strtrim(bonus) })
        return true
    end
    bonus = Match(PATTERNS.set_bonus, text)
    if bonus then
        state.members = false
        tinsert(set.bonuses, { text = strtrim(bonus) })
        return true
    end
    if state.members then
        tinsert(set.items, strtrim(text))
        return true
    end
    return false
end

-- Everything of the tooltip that GetItemInfo does not return. Numbers are 0,
-- texts "" and lists empty when the tooltip has no such line, so the website
-- can tell "nothing" from "not read". item = the base fields read so far.
-- Second result: the item set as the tooltip shows it, nil without a set.
function ns.ReadTooltip(itemID, link, item)
    if not C_TooltipInfo then return nil end
    local data = Safe(C_TooltipInfo.GetItemByID(itemID), "item.tooltip")
    local lines = data and Safe(data.lines, "item.tooltip.lines")
    if type(lines) ~= "table" then return nil end

    local values = {
        unique = false, unique_count = 0, unique_equipped = false,
        armor = 0, block = 0, durability = 0, weapon_speed = 0, container_slots = 0,
        charges = 0, ammo_dps = 0,
        starts_quest = false, openable = false, readable = false, locked = false,
        conjured = false, random_enchant = false,
        required_skill = "", required_skill_rank = 0,
        required_reputation = "", required_standing = 0,
        required_spell = "",
        classes = {}, races = {}, stats = {}, other_stats = {}, damage = {}, spells = {}, other_lines = {},
    }

    local stats = link and Safe(C_Item.GetItemStats(link), "item.stats")
    if type(stats) == "table" then
        for key, value in pairs(stats) do
            if key == "RESISTANCE0_NAME" then
                values.armor = value
            elseif value ~= 0 then
                if STATS[key] then
                    values.stats[STATS[key]] = value
                else
                    values.other_stats[key] = value
                end
            end
        end
    end

    local set
    if item.set_id then
        set = { name = Safe(C_Item.GetItemSetInfo(item.set_id), "item.set.name"), items = {}, bonuses = {} }
    end
    local setState = {}

    local seenSchools = {}
    for i = 2, #lines do  -- line 1 is the name
        local line = lines[i]
        local left = Safe(line.leftText, "item.tooltip.left")
        local right = Safe(line.rightText, "item.tooltip.right")
        local lineType = Safe(line.type, "item.tooltip.type")
        left = type(left) == "string" and strtrim(StripColors(left)) or ""
        right = type(right) == "string" and strtrim(StripColors(right)) or ""

        if left == "" then
            setState.members = false
        elseif set and ReadSetLine(set, left, setState) then
            -- part of the set block
        else
            local damage = ParseDamage(left)
            local trigger, spellText = ParseSpell(left, lineType)
            local durability = select(2, Match(PATTERNS.durability, left))
            local block = Match(PATTERNS.block, left)
            local slots = Match(PATTERNS.bag, left)
            local classes = Match(PATTERNS.classes, left)
            local races = Match(PATTERNS.races, left)
            local uniqueCount = Match(PATTERNS.unique_count, left)
            local charges = MatchCharges(left)
            local ammo = Match(PATTERNS.ammo_dps, left)
            local skill, skillRank = Match(PATTERNS.skill, left)
            local faction, standing = Match(PATTERNS.reputation, left)
            standing = standing and STANDINGS[strtrim(standing)]

            if damage then
                if not seenSchools[damage.school] then
                    seenSchools[damage.school] = true
                    tinsert(values.damage, damage)
                end
                -- the speed stands on the right of the first damage line: "Speed 2.60"
                local speed = Number(right:match("(%d+[%.,]%d+)"))
                if speed and values.weapon_speed == 0 then values.weapon_speed = math.floor(speed * 1000 + 0.5) end
            elseif trigger and spellText ~= "" then
                tinsert(values.spells, { trigger = trigger, text = spellText })
            elseif left == ITEM_UNIQUE then
                values.unique = true
                values.unique_count = 1
            elseif uniqueCount then
                values.unique_count = tonumber(uniqueCount) or 0
            elseif FLAGS[left] then
                values[FLAGS[left]] = true
            elseif durability then
                values.durability = tonumber(durability) or 0
            elseif block then
                values.block = tonumber(block) or 0
            elseif slots then
                values.container_slots = tonumber(slots) or 0
            elseif charges then
                values.charges = tonumber(charges) or 0
            elseif ammo and Number(ammo) then
                values.ammo_dps = Number(ammo)
            elseif classes then
                for name in classes:gmatch("[^,]+") do
                    local token = CLASSES[strtrim(name)]
                    if token then tinsert(values.classes, token) end
                end
            elseif races then
                for name in races:gmatch("[^,]+") do
                    local token = RACES[strtrim(name)]
                    if token then tinsert(values.races, token) end
                end
            elseif skill then
                values.required_skill = strtrim(skill)
                values.required_skill_rank = tonumber(skillRank) or 0
            elseif faction and standing then
                values.required_reputation = strtrim(faction)
                values.required_standing = standing
            elseif IsKnownLine(left, lineType, item) then
                -- repeats base data
            elseif Match(PATTERNS.requires, left) and not faction then
                values.required_spell = strtrim(Match(PATTERNS.requires, left))
            else
                tinsert(values.other_lines, right ~= "" and { left = left, right = right } or { left = left })
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
    return values, set
end
