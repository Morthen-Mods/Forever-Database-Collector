-- Forever-Database-Collector/Units.lua
-- NPCs and objects: name, level, rank, reaction, services, spawn points and vendor wares.
local _, ns = ...

local Safe, SafeBool = ns.Safe, ns.SafeBool

-- Only one spawn per GUID per session (every spawn has its own GUID)
local spawnedGUIDs = {}

-- For NPCs with a title, the second tooltip line is the subname ("<General Goods>"),
-- otherwise it is the level line. The level line is recognized by digits or "??".
local function GetSubname(unit)
    local data = Safe(C_TooltipInfo.GetUnit(unit), "npc.tooltip")
    local lines = data and Safe(data.lines, "npc.tooltip.lines")
    local line = lines and Safe(lines[2], "npc.tooltip.line")
    local text = line and Safe(line.leftText, "npc.subname")
    if type(text) ~= "string" or text == "" then return nil end
    if text:find("%d") or text:find("%?%?") then return nil end
    return (text:gsub("^<(.*)>$", "%1"))
end

local function RecordSpawn(kind, id, guid)
    if spawnedGUIDs[guid] then return end
    local uiMapID, x, y = ns.GetPlayerPosition()
    if not uiMapID then return end
    spawnedGUIDs[guid] = true

    -- 1 % grid per axis so the same spawn is not stored twice
    local key = id .. ":" .. uiMapID .. ":" .. math.floor(x) .. ":" .. math.floor(y)
    if kind == "npc" then
        ns.AddUnique("npc_spawns", key, { npc_id = id, ui_map_id = uiMapID, x = x, y = y })
    else
        ns.AddUnique("object_spawns", key, { object_id = id, ui_map_id = uiMapID, x = x, y = y })
    end
end

local function RecordNpc(unit, id)
    local npc = ns.GetEntry("npcs", id)
    ns.Merge(npc, {
        name = UnitName(unit),
        rank = UnitClassification(unit),    -- normal, elite, rare, rareelite, worldboss
    }, "npc")

    local subname = GetSubname(unit)
    if subname then npc.subname = subname end

    -- Level as a range, since many NPCs spawn with varying levels (-1 = "??")
    local level = Safe(UnitLevel(unit), "npc.level")
    if level and level > 0 then
        npc.min_level = math.min(npc.min_level or level, level)
        npc.max_level = math.max(npc.max_level or level, level)
    end

    -- Reaction per player faction; npcs.friendly_to is derived from it
    local reaction = Safe(UnitReaction(unit, "player"), "npc.reaction")
    local faction = Safe(UnitFactionGroup("player"), "player.faction")
    if reaction and faction then
        npc.reactions = npc.reactions or {}
        npc.reactions[faction] = reaction
    end
end

-- Records the unit; withSpawn only when it is reliably within range
function ns.RecordUnit(unit, withSpawn)
    local guid = Safe(UnitGUID(unit), "unit.guid")
    local kind, id = ns.ParseGUID(guid)
    if not kind then return nil end

    if kind == "npc" then
        if SafeBool(UnitPlayerControlled(unit), "unit.controlled") then return nil end   -- companions, totems
        RecordNpc(unit, id)
    else
        ns.Merge(ns.GetEntry("objects", id), { name = UnitName(unit) }, "object")
    end

    if withSpawn then RecordSpawn(kind, id, guid) end
    return kind, id
end

-- Spawn for an object whose GUID is known without a unit token (e.g. when looting)
function ns.RecordObjectSpawn(id, guid)
    RecordSpawn("object", id, guid)
end

-- ---------------------------------------------------------------------------
-- Services: what an NPC offers, named after the npc_flags bits of the schema.
-- Only services that were seen are stored; a missing one says nothing.
-- ---------------------------------------------------------------------------

local SERVICES = {}
for interaction, service in pairs({
    Gossip = "gossip", QuestGiver = "quest_giver", Merchant = "vendor", Vendor = "vendor",
    TaxiNode = "flight_master", Trainer = "trainer", Banker = "banker", CharacterBanker = "banker",
    Registrar = "petitioner", PetitionVendor = "petitioner", GuildTabardVendor = "tabard_designer",
    SpiritHealer = "spirit_healer", AreaSpiritHealer = "spirit_guide", Binder = "innkeeper",
    Auctioneer = "auctioneer", StableMaster = "stable_master", BattleMaster = "battlemaster",
}) do
    local value = Enum.PlayerInteractionType and Enum.PlayerInteractionType[interaction]
    if value then SERVICES[value] = service end
end

function ns.AddNpcService(npcID, service)
    local npc = ns.GetEntry("npcs", npcID)
    npc.services = npc.services or {}
    npc.services[service] = true
end

-- Fires for every NPC window: vendor, trainer, flight master, bank …
ns:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(interactionType)
    local service = SERVICES[Safe(interactionType, "npc.interaction")]
    if not service then return end
    local kind, id = ns.RecordUnit("npc", true)
    if kind == "npc" then ns.AddNpcService(id, service) end
end)

-- Target and mouseover: spawn only when the unit is close (about 10 yards)
local function OnUnitSeen(unit)
    if not SafeBool(UnitExists(unit), "unit.exists") then return end
    if SafeBool(UnitIsDead(unit), "unit.dead") then return end
    local close = not InCombatLockdown() and SafeBool(CheckInteractDistance(unit, 3), "unit.distance")
    ns.RecordUnit(unit, close)
end

ns:RegisterEvent("PLAYER_TARGET_CHANGED", function() OnUnitSeen("target") end)
ns:RegisterEvent("UPDATE_MOUSEOVER_UNIT", function() OnUnitSeen("mouseover") end)

-- Interaction: the player is standing right at the NPC or object
local function OnInteract() ns.RecordUnit("npc", true) end
ns:RegisterEvent("GOSSIP_SHOW", OnInteract)
ns:RegisterEvent("QUEST_GREETING", OnInteract)

-- Soft target of the interact key: the NPC or object right in front of the
-- player. Objects are no units otherwise, so this is the only way to learn
-- their name and position without looting them. Fires only with the client
-- option for the interact key (CVar softTargetInteract) turned on.
ns:RegisterEvent("PLAYER_SOFT_INTERACT_CHANGED", function(_, newTarget)
    if not ns.ParseGUID(newTarget, "softinteract.guid") then return end
    local inRange = SafeBool(UnitIsInInteractRange("softinteract"), "softinteract.range")
    local kind, id = ns.RecordUnit("softinteract", inRange)
    if kind == "object" then ns.lastObject = { id = id, time = GetTime() } end
end)

-- Vendor wares as a complete list (replaces the previous observation).
-- MERCHANT_UPDATE follows once the client has loaded missing item data.
local function RecordMerchant()
    local kind, npcID = ns.RecordUnit("npc", true)
    if kind ~= "npc" then return end

    local wares = {}
    for index = 1, Safe(GetMerchantNumItems(), "merchant.count") or 0 do
        local itemID = Safe(GetMerchantItemID(index), "merchant.item")
        if itemID then
            local info = Safe(C_MerchantFrame.GetItemInfo(index), "merchant.info")
            local extended = info and SafeBool(info.hasExtendedCost, "merchant.extended")
            table.insert(wares, {
                item_id = itemID,
                price = info and not extended and Safe(info.price, "merchant.price") or nil,   -- copper
            })
            ns.RecordItem(itemID)
        end
    end
    if #wares > 0 then
        ns.db.pending.npc_vendor_items[tostring(npcID)] = wares
    end
    ns.AddNpcService(npcID, "vendor")
    if CanMerchantRepair and SafeBool(CanMerchantRepair(), "merchant.repair") then
        ns.AddNpcService(npcID, "repair")
    end
end

ns:RegisterEvent("MERCHANT_SHOW", RecordMerchant)
ns:RegisterEvent("MERCHANT_UPDATE", RecordMerchant)
