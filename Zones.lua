-- Forever-Database-Collector/Zones.lua
-- Remembers every visited UiMap with its name and parent map. The website maps
-- it to the matching AreaTable zone via zones.ui_map_id.
local _, ns = ...

local recorded = {}

function ns.RecordZone(uiMapID)
    uiMapID = ns.Safe(uiMapID, "zone.id")
    if not uiMapID or recorded[uiMapID] then return end
    local info = ns.Safe(C_Map.GetMapInfo(uiMapID), "zone.info")
    if not info then return end
    recorded[uiMapID] = true

    ns.Merge(ns.GetEntry("zones", uiMapID), {
        name = info.name,
        map_type = info.mapType,
        parent_ui_map_id = info.parentMapID,
    }, "zone")

    -- Record parent maps (continent) as well
    local parentID = ns.Safe(info.parentMapID, "zone.parent")
    if parentID and parentID > 0 then
        ns.RecordZone(parentID)
    end
end

local function RecordCurrentZone()
    ns.RecordZone(C_Map.GetBestMapForUnit("player"))
end

ns:RegisterEvent("PLAYER_ENTERING_WORLD", RecordCurrentZone)
ns:RegisterEvent("ZONE_CHANGED_NEW_AREA", RecordCurrentZone)
