-- Forever-Database-Collector/Locales.lua
-- UI texts. English is the default; German overrides it in the German client.
-- If a key is missing, the key itself is shown.
local _, ns = ...

local L = setmetatable({}, { __index = function(_, key) return key end })
ns.L = L

-- English (default)
L.DATE_FORMAT = "%Y-%m-%d %H:%M"
L.EXPORT_TITLE = "Forever Database – Export"
L.EXPORT_INFO = "%d KB of data, export %d KB. Copy with Ctrl+C and paste it on the website under /import."
L.SELECT_ALL = "Select all"
L.CLEAR = "Copied – clear data"
L.CLEAR_CONFIRM = "Really clear?"
L.CLEARED = "Collected data cleared."
L.STATUS_HEADER = "Version %s – collecting since %s"
L.COMMANDS = "Commands: /fdb export · /fdb minimap · /fdb debug"
L.DEBUG_ON = "Debug on."
L.DEBUG_OFF = "Debug off."
L.MINIMAP_SHOWN = "Minimap button shown."
L.MINIMAP_HIDDEN = "Minimap button hidden."
L.TOOLTIP_SINCE = "Collecting since %s"
L.TOOLTIP_CLICK = "Click: open export"
L.TOOLTIP_DRAG = "Drag: move button"

L.STAT_QUESTS = "Quests"
L.STAT_NPCS = "NPCs"
L.STAT_OBJECTS = "Objects"
L.STAT_ITEMS = "Items"
L.STAT_ZONES = "Zones"
L.STAT_SPAWNS = "Spawns"
L.STAT_LOOT = "Loot"
L.STAT_QUEST_GIVERS = "Quest givers"
L.STAT_KILL_OBJECTIVES = "Kill objectives"
L.STAT_VENDORS = "Vendors"
L.STAT_SECRETS = "Blocked values"
L.STAT_ERRORS = "Errors"

local locale = GetLocale()

if locale == "deDE" or locale == "deAT" then
    L.DATE_FORMAT = "%d.%m.%Y %H:%M"
    L.EXPORT_TITLE = "Forever Database – Export"
    L.EXPORT_INFO = "%d KB Daten, Export %d KB. Mit Strg+C kopieren und auf der Website unter /import einfügen."
    L.SELECT_ALL = "Alles markieren"
    L.CLEAR = "Kopiert – Daten löschen"
    L.CLEAR_CONFIRM = "Wirklich löschen?"
    L.CLEARED = "Gesammelte Daten gelöscht."
    L.STATUS_HEADER = "Version %s – gesammelt seit %s"
    L.COMMANDS = "Befehle: /fdb export · /fdb minimap · /fdb debug"
    L.DEBUG_ON = "Debug an."
    L.DEBUG_OFF = "Debug aus."
    L.MINIMAP_SHOWN = "Minimap-Button eingeblendet."
    L.MINIMAP_HIDDEN = "Minimap-Button ausgeblendet."
    L.TOOLTIP_SINCE = "Gesammelt seit %s"
    L.TOOLTIP_CLICK = "Klicken: Export öffnen"
    L.TOOLTIP_DRAG = "Ziehen: Button verschieben"

    L.STAT_QUESTS = "Quests"
    L.STAT_NPCS = "NPCs"
    L.STAT_OBJECTS = "Objekte"
    L.STAT_ITEMS = "Items"
    L.STAT_ZONES = "Zonen"
    L.STAT_SPAWNS = "Spawns"
    L.STAT_LOOT = "Loot"
    L.STAT_QUEST_GIVERS = "Questgeber"
    L.STAT_KILL_OBJECTIVES = "Killziele"
    L.STAT_VENDORS = "Händler"
    L.STAT_SECRETS = "Gesperrte Werte"
    L.STAT_ERRORS = "Fehler"
end
