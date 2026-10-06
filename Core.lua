-- Forever-Database-Collector/Core.lua
-- Shared foundation: SavedVariables, event dispatch and helper functions.
-- Collected data lives in db.pending and is named after the tables and
-- columns of the website's database schema.
local addonName, ns = ...

ns.name = addonName
ns.version = C_AddOns.GetAddOnMetadata(addonName, "Version") or "dev"

-- ---------------------------------------------------------------------------
-- Collected data
-- ---------------------------------------------------------------------------

-- Maps (key = ID as string) are merged when seen again,
-- lists collect individual observations.
local function NewPending()
    return {
        started_at = time(),

        zones = {},                 -- [ui_map_id] = { name, map_type, parent_ui_map_id }
        quests = {},                -- [quest_id]  = { title, details, level, … }
        npcs = {},                  -- [npc_id]    = { name, subname, min_level, max_level, rank, reactions }
        objects = {},               -- [object_id] = { name }
        items = {},                 -- [item_id]   = { name, quality, … }
        npc_vendor_items = {},      -- [npc_id]    = { { item_id, price }, … }

        quest_npcs = {},            -- { quest_id, npc_id, role }
        quest_objects = {},         -- { quest_id, object_id, role }
        quest_items = {},           -- { quest_id, item_id, role }   (item starts quest)
        quest_accepts = {},         -- { quest_id, race, class, faction, level }
        quest_objective_kills = {}, -- { quest_id, index, npc_id }
        quest_lines = {},           -- [quest_line_id] = { name, quests }   (only if the client knows it)
        quest_chain_hints = {},     -- { quest_id, prev_quest_id, rank, seconds, same_giver, offered, seen_before }

        npc_spawns = {},            -- { npc_id, ui_map_id, x, y }
        object_spawns = {},         -- { object_id, ui_map_id, x, y }
        npc_loot = {},              -- { npc_id, ui_map_id, items = { { item_id, count }, … } }
        object_loot = {},           -- { object_id, ui_map_id, items = { … } }
    }
end

function ns:ResetPending()
    ns.db.pending = NewPending()
    ns.db.keys = {}
    ns.db.errors = {}
    ns.db.secrets = {}
    ns.db.stats = {}
end

-- Collector errors are counted and exported so they can be analyzed
function ns:LogError(event, err)
    local message = tostring(err)
    local key = event .. ": " .. message
    ns.db.errors[key] = (ns.db.errors[key] or 0) + 1
    ns:Debug(key)
end

-- ---------------------------------------------------------------------------
-- Event dispatch (several files may subscribe to the same event)
-- ---------------------------------------------------------------------------

local events = CreateFrame("Frame")
local handlers = {}

function ns:RegisterEvent(event, handler)
    if not handlers[event] then
        handlers[event] = {}
        events:RegisterEvent(event)
    end
    table.insert(handlers[event], handler)
end

events:SetScript("OnEvent", function(_, event, ...)
    if not ns.db then return end
    for _, handler in ipairs(handlers[event]) do
        -- An error in one collector must not block the others
        local ok, err = pcall(handler, ...)
        if not ok then ns:LogError(event, err) end
    end
end)

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, loadedAddon)
    if loadedAddon ~= addonName then return end
    self:UnregisterEvent("ADDON_LOADED")

    ForeverDatabaseCollectorDB = ForeverDatabaseCollectorDB or {}
    ns.db = ForeverDatabaseCollectorDB
    ns.db.settings = ns.db.settings or { debug = false }
    if not ns.db.pending then ns:ResetPending() end
    -- Data collected by an older version lacks newer collections
    for key, value in pairs(NewPending()) do
        if ns.db.pending[key] == nil then ns.db.pending[key] = value end
    end
    ns.db.keys = ns.db.keys or {}
    ns.db.errors = ns.db.errors or {}
    ns.db.secrets = ns.db.secrets or {}
    ns.db.stats = ns.db.stats or {}
end)

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- Secret Values
-- ---------------------------------------------------------------------------
-- The client can mark return values as "secret" (e.g. unit data in combat
-- or in instances). Such values cannot be compared, used in arithmetic,
-- tested or stored. Every API value therefore goes through ns.Safe before
-- it is used. Blocked values are counted per call site and exported, which
-- shows what data the client withholds.

local function IsSecret(value)
    if issecretvalue and issecretvalue(value) then return true end
    -- Tables can be secret themselves or return secret fields on access
    if type(value) == "table" and issecrettable and issecrettable(value) then return true end
    return false
end

-- Counts in and out of combat separately, since the client blocks a lot only in combat
function ns:CountSecret(context)
    if not context or not ns.db then return end
    if InCombatLockdown() then context = context .. " [combat]" end
    ns.db.secrets[context] = (ns.db.secrets[context] or 0) + 1
end

-- General diagnostic counters (e.g. how often kill attribution succeeds)
function ns:CountStat(name)
    if not ns.db then return end
    ns.db.stats[name] = (ns.db.stats[name] or 0) + 1
end

-- Returns the value, or nil if it is secret (context = call site name for the statistics)
function ns.Safe(value, context)
    if IsSecret(value) then
        ns:CountSecret(context)
        return nil
    end
    return value
end

-- For booleans: secret counts as false instead of raising an error inside the if
function ns.SafeBool(value, context)
    return ns.Safe(value, context) == true
end

function ns.IsUsable(value)
    if IsSecret(value) then return false end
    return value ~= nil
end

-- "Creature-0-1-0-12-299-0000ABCDEF" -> "npc", 299
-- "GameObject-0-1-0-12-1617-0000ABCDEF" -> "object", 1617
local GUID_KINDS = { Creature = "npc", Vehicle = "npc", GameObject = "object" }

function ns.ParseGUID(guid, context)
    guid = ns.Safe(guid, context)
    if type(guid) ~= "string" then return nil end
    local unitType, _, _, _, _, id = strsplit("-", guid)
    local kind = GUID_KINDS[unitType]
    id = tonumber(id)
    if not kind or not id or id == 0 then return nil end
    return kind, id
end

-- GUID of a unit token, only if it is readable
function ns.UnitID(unit, context)
    return ns.ParseGUID(UnitGUID(unit), context)
end

local function Round(value, decimals)
    local factor = 10 ^ decimals
    return math.floor(value * factor + 0.5) / factor
end

-- Player position in map percent (0–100), as in npc_spawns.x / y
function ns.GetPlayerPosition()
    local uiMapID = ns.Safe(C_Map.GetBestMapForUnit("player"), "position.map")
    if not uiMapID then return nil end
    local position = ns.Safe(C_Map.GetPlayerMapPosition(uiMapID, "player"), "position.vector")
    if not position then return nil end
    local x, y = position:GetXY()
    x, y = ns.Safe(x, "position.x"), ns.Safe(y, "position.y")
    if not x or not y or (x == 0 and y == 0) then return nil end
    ns.RecordZone(uiMapID)
    return uiMapID, Round(x * 100, 2), Round(y * 100, 2)
end

-- Inserts an entry into a list only once (the key is kept until the data is cleared)
function ns.AddUnique(listName, key, entry)
    local fullKey = listName .. ":" .. key
    if ns.db.keys[fullKey] then return false end
    ns.db.keys[fullKey] = true
    table.insert(ns.db.pending[listName], entry)
    return true
end

-- Returns a map entry, creating it if needed
function ns.GetEntry(mapName, id)
    local map = ns.db.pending[mapName]
    local key = tostring(id)
    map[key] = map[key] or {}
    return map[key]
end

-- Copies only values that are actually set and readable.
-- context (optional) is appended per field to the secret statistics, e.g. "npc.name"
function ns.Merge(target, values, context)
    for key, value in pairs(values) do
        value = ns.Safe(value, context and (context .. "." .. key))
        if value ~= nil and value ~= "" then
            target[key] = value
        end
    end
    return target
end

function ns.ItemIDFromLink(link, context)
    link = ns.Safe(link, context)
    if type(link) ~= "string" then return nil end
    return tonumber(link:match("item:(%d+)"))
end

-- ---------------------------------------------------------------------------
-- Output
-- ---------------------------------------------------------------------------

local PREFIX = "|cff33ff99Forever DB|r:"

function ns:Print(...)
    print(PREFIX, ...)
end

function ns:Debug(...)
    if ns.db and ns.db.settings.debug then
        print("|cffff9900Forever DB debug|r:", ...)
    end
end
