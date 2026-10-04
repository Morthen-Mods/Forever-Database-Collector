-- Forever-Database-Collector/Export.lua
-- Export dialog and slash commands.
-- Format: "FDB1:" .. Base64(Gzip(JSON)). The website's import page checks the prefix.
local addonName, ns = ...
local L = ns.L

local FORMAT_PREFIX = "FDB1:"

local function CountEntries(value)
    local count = 0
    for _ in pairs(value) do count = count + 1 end
    return count
end

local function BuildExportString()
    local _, build, _, interface = GetBuildInfo()
    local payload = {
        format = 1,
        meta = {
            addon = addonName,
            addon_version = ns.version,
            build = build,
            interface = interface,
            locale = GetLocale(),
            realm = GetRealmName(),
            started_at = ns.db.pending.started_at,
            exported_at = time(),
        },
        data = ns.db.pending,
        errors = ns.db.errors,      -- { ["EVENT: message"] = count }
        secrets = ns.db.secrets,    -- { ["call site"] = number of blocked values }
        stats = ns.db.stats,        -- diagnostic counters
    }

    local json = C_EncodingUtil.SerializeJSON(payload, { ignoreSerializationErrors = true })
    local compressed = C_EncodingUtil.CompressString(json, Enum.CompressionMethod.Gzip)
    return FORMAT_PREFIX .. C_EncodingUtil.EncodeBase64(compressed), #json
end

-- ---------------------------------------------------------------------------
-- Dialog
-- ---------------------------------------------------------------------------

local frame

local function CreateExportFrame()
    frame = CreateFrame("Frame", "ForeverDatabaseCollectorExportFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(520, 360)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame.TitleText:SetText(L.EXPORT_TITLE)
    tinsert(UISpecialFrames, frame:GetName())  -- closes with Escape

    frame.info = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.info:SetPoint("TOPLEFT", 14, -32)
    frame.info:SetPoint("TOPRIGHT", -14, -32)
    frame.info:SetJustifyH("LEFT")

    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 14, -64)
    scroll:SetPoint("BOTTOMRIGHT", -32, 44)

    local editBox = CreateFrame("EditBox", nil, scroll)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetFontObject(ChatFontSmall)
    editBox:SetWidth(460)
    editBox:SetScript("OnEscapePressed", function() frame:Hide() end)
    -- Read-only: any input restores the export text
    editBox:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            self:SetText(frame.exportText or "")
            self:HighlightText()
        end
    end)
    scroll:SetScrollChild(editBox)
    frame.editBox = editBox

    local selectButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    selectButton:SetSize(140, 24)
    selectButton:SetPoint("BOTTOMLEFT", 12, 12)
    selectButton:SetText(L.SELECT_ALL)
    selectButton:SetScript("OnClick", function()
        editBox:SetFocus()
        editBox:HighlightText()
    end)

    -- Two-step instead of a popup: first click asks, second click clears
    local clearButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    clearButton:SetSize(220, 24)
    clearButton:SetPoint("BOTTOMRIGHT", -12, 12)
    clearButton:SetScript("OnClick", function(self)
        if not self.confirm then
            self.confirm = true
            self:SetText(L.CLEAR_CONFIRM)
            return
        end
        ns:ResetPending()
        ns:Print(L.CLEARED)
        frame:Hide()
    end)
    frame.clearButton = clearButton
end

-- Reset on every open. Not via OnShow: a newly created frame is already
-- visible, so OnShow would never fire on the first open.
local function ResetClearButton()
    frame.clearButton.confirm = false
    frame.clearButton:SetText(L.CLEAR)
end

function ns:ShowExport()
    if not frame then CreateExportFrame() end

    local text, jsonSize = BuildExportString()
    frame.exportText = text
    frame.editBox:SetText(text)
    frame.info:SetText(L.EXPORT_INFO:format(math.ceil(jsonSize / 1024), math.ceil(#text / 1024)))
    ResetClearButton()
    frame:Show()
    frame.editBox:SetFocus()
    frame.editBox:HighlightText()
end

-- ---------------------------------------------------------------------------
-- Slash commands
-- ---------------------------------------------------------------------------

local function SumCounts(map)
    local total = 0
    for _, count in pairs(map) do total = total + count end
    return total
end

-- Collected amounts as an ordered list; used by /fdb and the minimap tooltip.
-- warn = the value is a problem counter and is highlighted once it is > 0
function ns:GetStats()
    local p = ns.db.pending
    return {
        { label = L.STAT_QUESTS, value = CountEntries(p.quests) },
        { label = L.STAT_NPCS, value = CountEntries(p.npcs) },
        { label = L.STAT_OBJECTS, value = CountEntries(p.objects) },
        { label = L.STAT_ITEMS, value = CountEntries(p.items) },
        { label = L.STAT_ZONES, value = CountEntries(p.zones) },
        { label = L.STAT_SPAWNS, value = #p.npc_spawns + #p.object_spawns },
        { label = L.STAT_LOOT, value = #p.npc_loot + #p.object_loot },
        { label = L.STAT_QUEST_GIVERS, value = #p.quest_npcs + #p.quest_objects + #p.quest_items },
        { label = L.STAT_KILL_OBJECTIVES, value = #p.quest_objective_kills },
        { label = L.STAT_VENDORS, value = CountEntries(p.npc_vendor_items) },
        { label = L.STAT_SECRETS, value = SumCounts(ns.db.secrets), warn = true },
        { label = L.STAT_ERRORS, value = SumCounts(ns.db.errors), warn = true },
    }
end

function ns:GetCollectingSince()
    return date(L.DATE_FORMAT, ns.db.pending.started_at)
end

local function PrintStatus()
    ns:Print(L.STATUS_HEADER:format(ns.version, ns:GetCollectingSince()))
    local parts = {}
    for _, stat in ipairs(ns:GetStats()) do
        table.insert(parts, stat.label .. " " .. stat.value)
    end
    ns:Print(table.concat(parts, " · "))
    ns:Print(L.COMMANDS)
end

SLASH_FOREVERDATABASECOLLECTOR1 = "/fdb"
SlashCmdList["FOREVERDATABASECOLLECTOR"] = function(msg)
    local command = (msg:match("^(%S*)") or ""):lower()

    if command == "export" then
        ns:ShowExport()
    elseif command == "minimap" then
        ns:ToggleMinimapButton()
    elseif command == "debug" then
        ns.db.settings.debug = not ns.db.settings.debug
        ns:Print(ns.db.settings.debug and L.DEBUG_ON or L.DEBUG_OFF)
    else
        PrintStatus()
    end
end
