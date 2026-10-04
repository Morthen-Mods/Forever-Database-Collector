-- Forever-Database-Collector/Minimap.lua
-- Round button at the minimap edge: the tooltip shows the collected amounts,
-- any click opens the export. Holding the mouse button drags it around the
-- minimap; the angle is saved.
local _, ns = ...
local L = ns.L

local DEFAULT_ANGLE = 225   -- degrees, bottom left
local button

-- Position on a circle around the minimap
local function UpdatePosition()
    local angle = math.rad(ns.db.settings.minimap.angle)
    local radius = Minimap:GetWidth() / 2 + 5
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

-- While dragging, the button follows the cursor along the circle
local function OnDragUpdate()
    local mx, my = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    local cx, cy = Minimap:GetCenter()
    ns.db.settings.minimap.angle = math.deg(math.atan2(my / scale - cy, mx / scale - cx))
    UpdatePosition()
end

local function ShowTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("Forever Database Collector")
    GameTooltip:AddLine(L.TOOLTIP_SINCE:format(ns:GetCollectingSince()), 0.7, 0.7, 0.7)
    GameTooltip:AddLine(" ")
    for _, stat in ipairs(ns:GetStats()) do
        -- Highlight errors and blocked values only when there are any
        local r, g, b = 1, 1, 1
        if stat.warn and stat.value > 0 then r, g, b = 1, 0.5, 0.3 end
        GameTooltip:AddDoubleLine(stat.label, stat.value, 1, 0.82, 0, r, g, b)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L.TOOLTIP_CLICK, 0.2, 1, 0.2)
    GameTooltip:AddLine(L.TOOLTIP_DRAG, 0.7, 0.7, 0.7)
    GameTooltip:Show()
end

local function CreateButton()
    button = CreateFrame("Button", "ForeverDatabaseCollectorMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    -- Same layout as Blizzard's own minimap buttons: background, icon, ring
    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    background:SetSize(20, 20)
    background:SetPoint("TOPLEFT", 7, -5)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
    icon:SetSize(17, 17)
    icon:SetPoint("TOPLEFT", 7, -6)
    icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")

    button:SetScript("OnClick", function()
        GameTooltip:Hide()
        ns:ShowExport()
    end)
    button:SetScript("OnEnter", ShowTooltip)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button:SetScript("OnDragStart", function(self)
        GameTooltip:Hide()
        self:SetScript("OnUpdate", OnDragUpdate)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    UpdatePosition()
end

function ns:ToggleMinimapButton()
    local settings = ns.db.settings.minimap
    settings.hidden = not settings.hidden
    button:SetShown(not settings.hidden)
    ns:Print(settings.hidden and L.MINIMAP_HIDDEN or L.MINIMAP_SHOWN)
end

ns:RegisterEvent("PLAYER_LOGIN", function()
    ns.db.settings.minimap = ns.db.settings.minimap or { angle = DEFAULT_ANGLE, hidden = false }
    CreateButton()
    button:SetShown(not ns.db.settings.minimap.hidden)
end)
