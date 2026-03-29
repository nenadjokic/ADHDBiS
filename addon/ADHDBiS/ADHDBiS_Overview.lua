-- ADHDBiS Overview: Gear overview, crest tracker, enchant/gem audit
-- =============================================================================

local addonName, ns = ...

-- ============================================================
-- SAVED VARIABLES
-- ============================================================

ADHDBiS_OverviewDB = ADHDBiS_OverviewDB or {}

local function GetOverviewDB()
    local db = ADHDBiS_OverviewDB
    if not db.width then db.width = 740 end
    if not db.height then db.height = 600 end
    return db
end

-- ============================================================
-- CONSTANTS
-- ============================================================

local SLOT_ORDER = {
    { name = "Head",     id = 1 },
    { name = "Neck",     id = 2 },
    { name = "Shoulder", id = 3 },
    { name = "Back",     id = 15 },
    { name = "Chest",    id = 5 },
    { name = "Wrist",    id = 9 },
    { name = "Hands",    id = 10 },
    { name = "Waist",    id = 6 },
    { name = "Legs",     id = 7 },
    { name = "Feet",     id = 8 },
    { name = "Ring 1",   id = 11 },
    { name = "Ring 2",   id = 12 },
    { name = "Trinket 1",id = 13 },
    { name = "Trinket 2",id = 14 },
    { name = "Weapon",   id = 16 },
    { name = "Off Hand", id = 17 },
}

-- Enchantable slots in Midnight
local ENCHANTABLE = {
    [1] = true,   -- Head
    [3] = true,   -- Shoulders
    [5] = true,   -- Chest
    [7] = true,   -- Legs
    [8] = true,   -- Feet
    [11] = true,  -- Ring 1
    [12] = true,  -- Ring 2
    [16] = true,  -- Weapon
}

-- Crest colors for the UI bars
local CREST_COLORS = {
    ["Adventurer"] = { r = 0.40, g = 0.80, b = 0.40 },
    ["Veteran"]    = { r = 0.00, g = 0.44, b = 0.87 },
    ["Champion"]   = { r = 0.64, g = 0.21, b = 0.93 },
    ["Hero"]       = { r = 1.00, g = 0.50, b = 0.00 },
    ["Myth"]       = { r = 1.00, g = 0.80, b = 0.00 },
}

-- Fallback crest data (used when ADHDBiS_Data is not available)
local CRESTS_FALLBACK = {
    { name = "Adventurer", id = 3383, cap = 500 },
    { name = "Veteran",    id = 3341, cap = 500 },
    { name = "Champion",   id = 3343, cap = 500 },
    { name = "Hero",       id = 3345, cap = 500 },
    { name = "Myth",       id = 3347, cap = 200 },
}

-- Fallback upgrade tracks (used when ADHDBiS_Data is not available)
local TRACKS_FALLBACK = {
    { name = "Myth",       base = 272, top = 289 },
    { name = "Hero",       base = 259, top = 276 },
    { name = "Champion",   base = 246, top = 263 },
    { name = "Veteran",    base = 233, top = 250 },
    { name = "Adventurer", base = 220, top = 237 },
}

-- Build CRESTS and TRACKS from companion data or use fallbacks
local function GetCrests()
    if ADHDBiS_Data and ADHDBiS_Data.crests then
        local crests = {}
        for _, c in ipairs(ADHDBiS_Data.crests) do
            local color = CREST_COLORS[c.name] or { r = 0.7, g = 0.7, b = 0.7 }
            crests[#crests + 1] = {
                name = c.name, id = c.currencyID, cap = c.cap,
                r = color.r, g = color.g, b = color.b,
            }
        end
        return crests
    end
    local crests = {}
    for _, c in ipairs(CRESTS_FALLBACK) do
        local color = CREST_COLORS[c.name] or { r = 0.7, g = 0.7, b = 0.7 }
        crests[#crests + 1] = {
            name = c.name, id = c.id, cap = c.cap,
            r = color.r, g = color.g, b = color.b,
        }
    end
    return crests
end

local function GetTracks()
    if ADHDBiS_Data and ADHDBiS_Data.upgradeTracks then
        local tracks = {}
        for i = #ADHDBiS_Data.upgradeTracks, 1, -1 do
            local t = ADHDBiS_Data.upgradeTracks[i]
            tracks[#tracks + 1] = { name = t.name, base = t.base, top = t.top }
        end
        return tracks
    end
    return TRACKS_FALLBACK
end

local CRESTS -- populated on first use
local TRACKS -- populated on first use

-- Slot name aliases for BiS data matching
local SLOT_ALIASES = {
    [1]  = { "Head" },
    [2]  = { "Neck" },
    [3]  = { "Shoulders" },
    [5]  = { "Chest" },
    [6]  = { "Waist" },
    [7]  = { "Legs" },
    [8]  = { "Feet" },
    [9]  = { "Wrist" },
    [10] = { "Hands" },
    [11] = { "Finger1", "Ring 1", "Ring1" },
    [12] = { "Finger2", "Ring 2", "Ring2" },
    [13] = { "Trinket1", "Trinket 1" },
    [14] = { "Trinket2", "Trinket 2" },
    [15] = { "Back" },
    [16] = { "Weapon", "2h weapon", "1h weapon", "Main Hand", "Weapon (staff)", "Weapon (2h)", "Weapon (1h)", "Weapon (dagger)", "Weapon (wand)" },
    [17] = { "OffHand", "Off Hand", "Off-Hand" },
}

local ROW_HEIGHT = 22
local ICON_SIZE = 20

local QUALITY_COLORS = {
    [0] = "9D9D9D", [1] = "FFFFFF", [2] = "1EFF00",
    [3] = "0070DD", [4] = "A335EE", [5] = "FF8000",
    [6] = "E6CC80", [7] = "00CCFF",
}

-- ============================================================
-- TOOLTIP SCANNER
-- ============================================================

local scanTip = CreateFrame("GameTooltip", "ADHDBiSOverviewScanTip", nil, "GameTooltipTemplate")
scanTip:SetOwner(UIParent, "ANCHOR_NONE")

-- ============================================================
-- HELPER FUNCTIONS
-- ============================================================

local function GetUpgradeTrack(slotID)
    scanTip:ClearLines()
    scanTip:SetInventoryItem("player", slotID)
    for i = 1, scanTip:NumLines() do
        local line = _G["ADHDBiSOverviewScanTipTextLeft" .. i]
        if line then
            local text = line:GetText()
            if text then
                local track, rank, total = text:match("Upgrade Level:%s*(%S+)%s+(%d+)/(%d+)")
                if track and rank then
                    return track, tonumber(rank), tonumber(total)
                end
            end
        end
    end
    return nil, nil, nil
end

local function HasEmptySocket(slotID)
    scanTip:ClearLines()
    scanTip:SetInventoryItem("player", slotID)
    for i = 1, scanTip:NumLines() do
        local line = _G["ADHDBiSOverviewScanTipTextLeft" .. i]
        if line then
            local text = line:GetText()
            if text and text:find("Empty") and text:find("Socket") then
                return true
            end
        end
    end
    return false
end

local function HasFilledGem(slotID)
    scanTip:ClearLines()
    scanTip:SetInventoryItem("player", slotID)
    for i = 1, scanTip:NumLines() do
        local line = _G["ADHDBiSOverviewScanTipTextLeft" .. i]
        if line then
            local text = line:GetText()
            if text and text:find("Socket") and not text:find("Empty") then
                return true
            end
        end
    end
    return false
end

local function GetGemStatus(slotID)
    if HasEmptySocket(slotID) then
        return "empty", nil
    end
    local link = GetInventoryItemLink("player", slotID)
    if link then
        local gemName, gemLink = GetItemGem(link, 1)
        if gemLink then
            local gemIcon = C_Item.GetItemIconByID(GetItemInfoInstant(gemLink))
            return "filled", gemIcon
        end
    end
    if HasFilledGem(slotID) then
        return "filled", nil
    end
    return "none", nil
end

local function HasEnchant(slotID)
    scanTip:ClearLines()
    scanTip:SetInventoryItem("player", slotID)
    for i = 1, scanTip:NumLines() do
        local line = _G["ADHDBiSOverviewScanTipTextLeft" .. i]
        if line then
            local text = line:GetText()
            if text and text:find("Enchanted:") then
                return true
            end
        end
    end
    return false
end

local function GetStatPriority()
    if not ADHDBiS_Data or not ADHDBiS_Data.classes then return nil end
    local playerClass = UnitClass("player")
    local specIndex = GetSpecialization()
    if not playerClass or not specIndex then return nil end
    local _, specName = GetSpecializationInfo(specIndex)
    if not specName then return nil end
    local classData = ADHDBiS_Data.classes[playerClass]
    if not classData or not classData[specName] then return nil end
    for _, sourceName in ipairs({"Icy Veins", "Wowhead"}) do
        local sourceData = classData[specName][sourceName]
        if sourceData and sourceData.statPriority and sourceData.statPriority ~= "" then
            return sourceData.statPriority
        end
    end
    return nil
end

local function GetClassColor()
    local _, class = UnitClass("player")
    if class and RAID_CLASS_COLORS[class] then
        local c = RAID_CLASS_COLORS[class]
        return c.r, c.g, c.b
    end
    return 0.58, 0.51, 0.79
end

-- Gear source state for tabs
local selectedOverviewSource = "overall"

local function GetBiSItemForSlot(slotID, gearSource)
    if not ADHDBiS_Data or not ADHDBiS_Data.classes then return nil, nil end
    local playerClass = UnitClass("player")
    local specIndex = GetSpecialization()
    if not playerClass or not specIndex then return nil, nil end
    local _, specName = GetSpecializationInfo(specIndex)
    if not specName then return nil, nil end
    local classData = ADHDBiS_Data.classes[playerClass]
    if not classData or not classData[specName] then return nil, nil end

    -- Build search order based on selected source
    local searchOrder
    if gearSource == "raid" then
        searchOrder = {"raid", "overall"}
    elseif gearSource == "mythicplus" then
        searchOrder = {"mythicplus", "overall"}
    else
        searchOrder = {"overall", "raid", "mythicplus"}
    end

    for _, sourceName in ipairs({"Icy Veins", "Wowhead"}) do
        local sourceData = classData[specName][sourceName]
        if sourceData and sourceData.gear then
            for _, gearType in ipairs(searchOrder) do
                local gearList = sourceData.gear[gearType]
                if gearList then
                    local aliases = SLOT_ALIASES[slotID]
                    if aliases then
                        for _, item in ipairs(gearList) do
                            for _, alias in ipairs(aliases) do
                                if item.slot == alias then
                                    return item.itemID, item.name, item.source
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return nil, nil, nil
end

-- ============================================================
-- MAIN FRAME (resizable + movable)
-- ============================================================

local overviewFrame = CreateFrame("Frame", "ADHDBiSOverviewFrame", UIParent, "BackdropTemplate")
overviewFrame:SetSize(740, 600)
overviewFrame:SetPoint("CENTER")
overviewFrame:SetFrameStrata("HIGH")
overviewFrame:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
})
overviewFrame:SetBackdropColor(0.05, 0.05, 0.08, 0.92)
overviewFrame:SetBackdropBorderColor(0.4, 0.2, 0.6, 0.9)
overviewFrame:SetClampedToScreen(true)
overviewFrame:SetMovable(true)
overviewFrame:SetResizable(true)
overviewFrame:SetResizeBounds(600, 450, 1200, 900)
overviewFrame:EnableMouse(true)
overviewFrame:RegisterForDrag("LeftButton")
overviewFrame:SetScript("OnDragStart", overviewFrame.StartMoving)
overviewFrame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local db = GetOverviewDB()
    local point, _, relPoint, x, y = self:GetPoint()
    db.point = { point, relPoint, x, y }
end)
overviewFrame:Hide()

-- Resize handle
local resizeBtn = CreateFrame("Button", nil, overviewFrame)
resizeBtn:SetSize(16, 16)
resizeBtn:SetPoint("BOTTOMRIGHT", overviewFrame, "BOTTOMRIGHT", -4, 4)
resizeBtn:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
resizeBtn:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
resizeBtn:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
resizeBtn:SetScript("OnMouseDown", function() overviewFrame:StartSizing("BOTTOMRIGHT") end)
resizeBtn:SetScript("OnMouseUp", function()
    overviewFrame:StopMovingOrSizing()
    local db = GetOverviewDB()
    db.width = overviewFrame:GetWidth()
    db.height = overviewFrame:GetHeight()
end)

-- Close button
local closeBtn = CreateFrame("Button", nil, overviewFrame, "UIPanelCloseButton")
closeBtn:SetPoint("TOPRIGHT", overviewFrame, "TOPRIGHT", -2, -2)

tinsert(UISpecialFrames, "ADHDBiSOverviewFrame")

-- ============================================================
-- HEADER: Class + Spec + Stat Priority
-- ============================================================

local headerText = overviewFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
headerText:SetPoint("TOPLEFT", overviewFrame, "TOPLEFT", 12, -10)
headerText:SetText("Overview")

local statPrioText = overviewFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
statPrioText:SetPoint("TOPLEFT", headerText, "BOTTOMLEFT", 0, -2)
statPrioText:SetTextColor(0.7, 0.7, 0.7)

-- ============================================================
-- CREST TRACKER
-- ============================================================

local crestHeader = overviewFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
crestHeader:SetPoint("TOPLEFT", statPrioText, "BOTTOMLEFT", 0, -10)
crestHeader:SetText("|cFFFFD100Dawncrest Tracker|r")

local crestBars = {}
local function CreateCrestBars()
    if not CRESTS then CRESTS = GetCrests() end
    local anchor = crestHeader
    for i, crest in ipairs(CRESTS) do
        local row = CreateFrame("Frame", nil, overviewFrame)
        row:SetHeight(18)
        row:SetPoint("LEFT", overviewFrame, "LEFT", 12, 0)
        row:SetPoint("RIGHT", overviewFrame, "RIGHT", -12, 0)
        if i == 1 then
            row:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
        else
            row:SetPoint("TOPLEFT", crestBars[i - 1].row, "BOTTOMLEFT", 0, -2)
        end

        local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("LEFT", row, "LEFT", 0, 0)
        label:SetWidth(85)
        label:SetJustifyH("LEFT")
        label:SetText(crest.name)

        local valueTxt = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        valueTxt:SetPoint("LEFT", label, "RIGHT", 2, 0)
        valueTxt:SetWidth(60)
        valueTxt:SetJustifyH("RIGHT")

        local barBg = row:CreateTexture(nil, "BACKGROUND")
        barBg:SetPoint("LEFT", valueTxt, "RIGHT", 4, 0)
        barBg:SetPoint("RIGHT", row, "RIGHT", -100, 0)
        barBg:SetHeight(12)
        barBg:SetColorTexture(0.1, 0.1, 0.15, 0.8)

        local bar = CreateFrame("StatusBar", nil, row)
        bar:SetPoint("LEFT", valueTxt, "RIGHT", 4, 0)
        bar:SetPoint("RIGHT", row, "RIGHT", -100, 0)
        bar:SetHeight(12)
        bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        bar:SetStatusBarColor(crest.r, crest.g, crest.b, 0.9)
        bar:SetMinMaxValues(0, crest.cap)
        bar:SetValue(0)

        local availTxt = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        availTxt:SetPoint("LEFT", bar, "RIGHT", 6, 0)
        availTxt:SetWidth(90)
        availTxt:SetJustifyH("LEFT")
        availTxt:SetTextColor(0.7, 0.7, 0.7)

        crestBars[i] = { row = row, label = label, value = valueTxt, bar = bar, avail = availTxt, crest = crest }
    end
end

-- ============================================================
-- GEAR SOURCE TABS (Overall / Raid / M+)
-- ============================================================

local gearTitle = overviewFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")

local gearToggleFrame = CreateFrame("Frame", nil, overviewFrame)
gearToggleFrame:SetHeight(20)

local gearToggleBtns = {}

local function RefreshOverview() end -- forward declare

local function CreateGearToggle(label, source, anchor)
    local btn = CreateFrame("Button", nil, gearToggleFrame)
    btn:SetSize(55, 18)
    if anchor then
        btn:SetPoint("LEFT", anchor, "RIGHT", 4, 0)
    else
        btn:SetPoint("LEFT", gearToggleFrame, "LEFT", 0, 0)
    end
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.2, 0.2, 0.3, 0.6)
    btn.bg = bg
    local text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("CENTER")
    text:SetText(label)
    btn.label = text
    btn.source = source
    btn:SetScript("OnClick", function()
        selectedOverviewSource = source
        RefreshOverview()
    end)
    table.insert(gearToggleBtns, btn)
    return btn
end

local overallBtn = CreateGearToggle("Overall", "overall", nil)
local raidBtn = CreateGearToggle("Raid", "raid", overallBtn)
local mplusBtn = CreateGearToggle("M+", "mythicplus", raidBtn)

-- ============================================================
-- GEAR TABLE HEADER
-- ============================================================

local gearHeader = CreateFrame("Frame", nil, overviewFrame)
gearHeader:SetHeight(18)

local colSlot   = gearHeader:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
local colIlvl   = gearHeader:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
local colTrack  = gearHeader:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
local colGem    = gearHeader:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
local colEnch   = gearHeader:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
local colBiS    = gearHeader:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")

-- ============================================================
-- SCROLL FRAME FOR GEAR ROWS
-- ============================================================

local scrollFrame = CreateFrame("ScrollFrame", "ADHDBiSOverviewScroll", overviewFrame, "UIPanelScrollFrameTemplate")
local scrollChild = CreateFrame("Frame", nil, scrollFrame)
scrollChild:SetHeight(1)
scrollFrame:SetScrollChild(scrollChild)

local gearRows = {}

local function GetOrCreateRow(index)
    if gearRows[index] then return gearRows[index] end

    local row = CreateFrame("Frame", nil, scrollChild)
    row:SetHeight(ROW_HEIGHT)

    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    if index % 2 == 0 then
        bg:SetColorTexture(0.08, 0.08, 0.12, 0.5)
    else
        bg:SetColorTexture(0.05, 0.05, 0.08, 0.3)
    end

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.icon = icon

    local slotTxt = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    slotTxt:SetPoint("LEFT", icon, "RIGHT", 4, 0)
    slotTxt:SetWidth(65)
    slotTxt:SetJustifyH("LEFT")
    slotTxt:SetWordWrap(false)
    row.slotTxt = slotTxt

    local nameTxt = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameTxt:SetPoint("LEFT", slotTxt, "RIGHT", 2, 0)
    nameTxt:SetJustifyH("LEFT")
    nameTxt:SetWordWrap(false)
    row.nameTxt = nameTxt

    local ilvlTxt = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ilvlTxt:SetWidth(35)
    ilvlTxt:SetJustifyH("CENTER")
    row.ilvlTxt = ilvlTxt

    local trackTxt = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    trackTxt:SetWidth(80)
    trackTxt:SetJustifyH("LEFT")
    trackTxt:SetWordWrap(false)
    row.trackTxt = trackTxt

    local gemIcon = row:CreateTexture(nil, "ARTWORK")
    gemIcon:SetSize(16, 16)
    row.gemIcon = gemIcon

    local enchIcon = row:CreateTexture(nil, "ARTWORK")
    enchIcon:SetSize(14, 14)
    row.enchIcon = enchIcon

    local enchTxt = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    enchTxt:SetWidth(25)
    enchTxt:SetJustifyH("CENTER")
    row.enchTxt = enchTxt

    local bisTxt = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bisTxt:SetJustifyH("LEFT")
    bisTxt:SetWordWrap(false)
    row.bisTxt = bisTxt

    -- Hover highlight
    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(0.3, 0.3, 0.5, 0.2)

    -- Tooltip on hover - shows BiS info
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.bisName and self.bisName ~= "" then
            if self.equippedID and self.bisItemID and self.equippedID == self.bisItemID then
                GameTooltip:AddLine("|cFF00FF00" .. self.bisName .. "|r")
                GameTooltip:AddLine("|cFF00FF00This is your BiS item!|r", 0, 1, 0)
            else
                GameTooltip:AddLine("|cFFFFD100BiS: " .. self.bisName .. "|r")
            end
            if self.bisSource and self.bisSource ~= "" then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("|cFFBBBBBBDrops from:|r " .. self.bisSource, 1, 1, 1)
            end
            local sourceLabel = selectedOverviewSource == "mythicplus" and "Mythic+" or
                               selectedOverviewSource == "raid" and "Raid" or "Overall"
            GameTooltip:AddLine("|cFF888888Source list: " .. sourceLabel .. "|r", 0.5, 0.5, 0.5)
        else
            GameTooltip:AddLine("|cFF888888No BiS data for this slot|r")
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Gem icon tooltip
    row.gemIcon:EnableMouse(true)
    row.gemIcon:SetScript("OnEnter", function(self)
        if row.gemLink then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(row.gemLink)
            GameTooltip:Show()
        elseif row.gemStatus == "empty" then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("|cFFFF4444Empty Socket|r")
            GameTooltip:AddLine("This item has an empty prismatic socket.", 0.7, 0.7, 0.7, true)
            GameTooltip:Show()
        end
    end)
    row.gemIcon:SetScript("OnLeave", function() GameTooltip:Hide() end)

    gearRows[index] = row
    return row
end

-- ============================================================
-- PROGRESS BAR (BiS count)
-- ============================================================

local progressFrame = CreateFrame("Frame", nil, overviewFrame)
progressFrame:SetHeight(24)
progressFrame:SetPoint("BOTTOMLEFT", overviewFrame, "BOTTOMLEFT", 12, 8)
progressFrame:SetPoint("BOTTOMRIGHT", overviewFrame, "BOTTOMRIGHT", -28, 8)

local progressBg = progressFrame:CreateTexture(nil, "BACKGROUND")
progressBg:SetAllPoints()
progressBg:SetColorTexture(0.1, 0.1, 0.15, 0.8)

local progressBar = CreateFrame("StatusBar", nil, progressFrame)
progressBar:SetAllPoints()
progressBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
progressBar:SetStatusBarColor(0.85, 0.70, 0.20, 0.9)
progressBar:SetMinMaxValues(0, 16)
progressBar:SetValue(0)

local progressText = progressFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
progressText:SetPoint("CENTER", progressFrame, "CENTER", 0, 0)
progressText:SetTextColor(1, 1, 1)

-- ============================================================
-- LAYOUT HELPER (responsive column widths)
-- ============================================================

-- Column offsets calculated from frame width
local colOffsets = {}

local function CalcColumnOffsets()
    local frameW = overviewFrame:GetWidth() - 40
    local iconSlotW = ICON_SIZE + 4 + 65 + 2
    local ilvlW = 35
    local trackW = 80
    local gemW = 20
    local enchW = 25
    local gaps = 4 * 5
    local fixedW = iconSlotW + ilvlW + trackW + gemW + enchW + gaps
    local remaining = frameW - fixedW
    local nameW = math.floor(remaining * 0.5)
    local bisW = remaining - nameW
    colOffsets.nameW = nameW
    colOffsets.bisW = bisW
    colOffsets.ilvlX = iconSlotW + nameW + 4
    colOffsets.trackX = colOffsets.ilvlX + ilvlW + 4
    colOffsets.gemX = colOffsets.trackX + trackW + 4
    colOffsets.enchX = colOffsets.gemX + gemW + 4
    colOffsets.bisX = colOffsets.enchX + enchW + 4
end

local function LayoutColumns()
    CalcColumnOffsets()
    for _, row in pairs(gearRows) do
        row.nameTxt:SetWidth(colOffsets.nameW)
        row.ilvlTxt:ClearAllPoints()
        row.ilvlTxt:SetPoint("LEFT", row, "LEFT", colOffsets.ilvlX, 0)
        row.trackTxt:ClearAllPoints()
        row.trackTxt:SetPoint("LEFT", row, "LEFT", colOffsets.trackX, 0)
        row.gemIcon:ClearAllPoints()
        row.gemIcon:SetPoint("LEFT", row, "LEFT", colOffsets.gemX, 0)
        row.enchIcon:ClearAllPoints()
        row.enchIcon:SetPoint("LEFT", row, "LEFT", colOffsets.enchX + 5, 0)
        row.enchTxt:ClearAllPoints()
        row.enchTxt:SetPoint("LEFT", row, "LEFT", colOffsets.enchX, 0)
        row.bisTxt:ClearAllPoints()
        row.bisTxt:SetPoint("LEFT", row, "LEFT", colOffsets.bisX, 0)
        row.bisTxt:SetWidth(colOffsets.bisW)
    end
    colSlot:ClearAllPoints()
    colSlot:SetPoint("LEFT", gearHeader, "LEFT", ICON_SIZE + 4, 0)
    colSlot:SetText("|cFF888888Slot|r")
    colIlvl:ClearAllPoints()
    colIlvl:SetPoint("LEFT", gearHeader, "LEFT", colOffsets.ilvlX, 0)
    colIlvl:SetText("|cFF888888ilvl|r")
    colTrack:ClearAllPoints()
    colTrack:SetPoint("LEFT", gearHeader, "LEFT", colOffsets.trackX, 0)
    colTrack:SetText("|cFF888888Track|r")
    colGem:ClearAllPoints()
    colGem:SetPoint("LEFT", gearHeader, "LEFT", colOffsets.gemX, 0)
    colGem:SetText("|cFF888888Gem|r")
    colEnch:ClearAllPoints()
    colEnch:SetPoint("LEFT", gearHeader, "LEFT", colOffsets.enchX, 0)
    colEnch:SetText("|cFF888888Ench|r")
    colBiS:ClearAllPoints()
    colBiS:SetPoint("LEFT", gearHeader, "LEFT", colOffsets.bisX, 0)
    colBiS:SetText("|cFF888888BiS|r")
    scrollChild:SetWidth(scrollFrame:GetWidth())
end

-- ============================================================
-- REFRESH / POPULATE
-- ============================================================

RefreshOverview = function()
    if not overviewFrame:IsShown() then return end

    -- Header
    local playerClass = UnitClass("player")
    local specIndex = GetSpecialization()
    local specName = ""
    if specIndex then
        _, specName = GetSpecializationInfo(specIndex)
    end
    local cr, cg, cb = GetClassColor()
    headerText:SetText(string.format("|cFF%02x%02x%02x%s %s|r Overview",
        math.floor(cr * 255), math.floor(cg * 255), math.floor(cb * 255),
        specName or "", playerClass or ""))

    local statPrio = GetStatPriority()
    if statPrio then
        statPrioText:SetText("|cFFFFD100Stat Priority:|r " .. statPrio)
    else
        statPrioText:SetText("|cFF888888Stat Priority: Run companion app to scrape stat data|r")
    end
    statPrioText:Show()

    -- Crests
    for i, entry in ipairs(crestBars) do
        local info = C_CurrencyInfo.GetCurrencyInfo(entry.crest.id)
        if info then
            local totalEarned = info.totalEarned or info.quantity or 0
            local available = info.quantity or 0
            local cap = info.maxQuantity
            if not cap or cap == 0 then cap = entry.crest.cap end
            entry.bar:SetMinMaxValues(0, cap)
            entry.bar:SetValue(totalEarned)
            entry.value:SetText(totalEarned .. "/" .. cap)
            entry.avail:SetText(available .. " avail")
            if totalEarned >= cap then
                entry.value:SetTextColor(0.3, 1.0, 0.3)
            else
                entry.value:SetTextColor(0.9, 0.9, 0.9)
            end
            if available > 0 then
                entry.avail:SetTextColor(0.5, 1.0, 0.5)
            else
                entry.avail:SetTextColor(0.5, 0.5, 0.5)
            end
        else
            entry.value:SetText("?")
            entry.avail:SetText("")
            entry.bar:SetValue(0)
        end
    end

    -- Gear toggle button highlights
    for _, btn in ipairs(gearToggleBtns) do
        if btn.source == selectedOverviewSource then
            btn.bg:SetColorTexture(0.3, 0.2, 0.5, 0.8)
            btn.label:SetTextColor(1, 1, 1)
        else
            btn.bg:SetColorTexture(0.15, 0.15, 0.2, 0.6)
            btn.label:SetTextColor(0.6, 0.6, 0.6)
        end
    end

    -- Position gear section below crests
    local lastCrest = crestBars[#crestBars]
    gearTitle:ClearAllPoints()
    gearTitle:SetPoint("TOPLEFT", lastCrest.row, "BOTTOMLEFT", 0, -12)
    gearTitle:SetText("|cFFFFD100Equipped Gear|r")

    gearToggleFrame:ClearAllPoints()
    gearToggleFrame:SetPoint("LEFT", gearTitle, "RIGHT", 12, 0)
    gearToggleFrame:SetPoint("RIGHT", overviewFrame, "RIGHT", -28, 0)

    gearHeader:ClearAllPoints()
    gearHeader:SetPoint("TOPLEFT", gearTitle, "BOTTOMLEFT", 0, -4)
    gearHeader:SetPoint("RIGHT", overviewFrame, "RIGHT", -28, 0)

    scrollFrame:ClearAllPoints()
    scrollFrame:SetPoint("TOPLEFT", gearHeader, "BOTTOMLEFT", 0, -2)
    scrollFrame:SetPoint("BOTTOMRIGHT", progressFrame, "TOPRIGHT", -10, 6)

    LayoutColumns()

    -- Gear rows
    local bisCount = 0
    local totalSlots = 0
    for idx, slot in ipairs(SLOT_ORDER) do
        local row = GetOrCreateRow(idx)
        row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -(idx - 1) * ROW_HEIGHT)
        row:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)
        row:Show()

        local tex = GetInventoryItemTexture("player", slot.id)
        row.icon:SetTexture(tex or "Interface\\Icons\\INV_Misc_QuestionMark")
        row.icon:Show()

        row.slotTxt:SetText(slot.name)

        -- Item name + quality color
        local link = GetInventoryItemLink("player", slot.id)
        row.itemLink = link
        local itemName = ""
        local ilvl = 0
        if link then
            local name, _, quality = C_Item.GetItemInfo(link)
            if name then
                local col = QUALITY_COLORS[quality] or "FFFFFF"
                itemName = "|cFF" .. col .. name .. "|r"
            else
                itemName = "|cFF888888Loading...|r"
            end
            local effectiveIlvl = GetDetailedItemLevelInfo(link)
            if effectiveIlvl then ilvl = effectiveIlvl end
        else
            itemName = "|cFF555555Empty|r"
        end
        row.nameTxt:SetText(itemName)

        -- ilvl
        row.ilvlTxt:SetText(ilvl > 0 and tostring(ilvl) or "-")

        -- Upgrade track
        local trackName, trackRank, trackTotal = GetUpgradeTrack(slot.id)
        if trackName and trackRank then
            row.trackTxt:SetText(trackName .. " " .. trackRank .. "/" .. (trackTotal or 6))
        else
            row.trackTxt:SetText("-")
        end

        -- Gem status
        local gemStatus, gemIconTex = GetGemStatus(slot.id)
        row.gemStatus = gemStatus
        row.gemLink = nil
        if gemStatus == "filled" and link then
            local _, gemLink = GetItemGem(link, 1)
            row.gemLink = gemLink
        end
        if gemStatus == "filled" then
            row.gemIcon:SetTexture(gemIconTex or "Interface\\Icons\\INV_Misc_Gem_01")
            row.gemIcon:SetDesaturated(false)
            row.gemIcon:SetVertexColor(1, 1, 1)
            row.gemIcon:Show()
        elseif gemStatus == "empty" then
            row.gemIcon:SetTexture("Interface\\ItemSocketingFrame\\UI-EmptySocket-Prismatic")
            row.gemIcon:SetDesaturated(false)
            row.gemIcon:SetVertexColor(1, 0.3, 0.3)
            row.gemIcon:Show()
        else
            row.gemIcon:Hide()
        end

        -- Enchant status: icon / dash
        if ENCHANTABLE[slot.id] then
            if link and HasEnchant(slot.id) then
                row.enchIcon:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
                row.enchIcon:SetVertexColor(0, 1, 0)
                row.enchIcon:Show()
            else
                row.enchIcon:SetTexture("Interface\\RaidFrame\\ReadyCheck-NotReady")
                row.enchIcon:SetVertexColor(1, 0.3, 0.3)
                row.enchIcon:Show()
            end
            row.enchTxt:SetText("")
        else
            row.enchIcon:Hide()
            row.enchTxt:SetText("|cFF555555-|r")
        end

        -- BiS match (uses selected gear source)
        local equippedID = link and GetInventoryItemID("player", slot.id) or nil
        row.equippedID = equippedID
        row.bisItemID = nil
        row.bisName = nil
        row.bisSource = nil
        if link then
            totalSlots = totalSlots + 1
            local bisID, bisName, bisSource = GetBiSItemForSlot(slot.id, selectedOverviewSource)
            row.bisItemID = bisID
            row.bisName = bisName
            row.bisSource = bisSource
            if bisID and equippedID == bisID then
                row.bisTxt:SetText("|cFF00FF00BiS|r")
                bisCount = bisCount + 1
            elseif bisID and bisName then
                row.bisTxt:SetText("|cFFFF4444" .. bisName .. "|r")
            else
                row.bisTxt:SetText("|cFF555555No data|r")
            end
        else
            row.bisTxt:SetText("")
        end
    end

    for i = #SLOT_ORDER + 1, #gearRows do
        gearRows[i]:Hide()
    end

    scrollChild:SetHeight(#SLOT_ORDER * ROW_HEIGHT + 4)

    -- Progress bar
    local sourceLabel = selectedOverviewSource == "mythicplus" and "M+" or
                       selectedOverviewSource == "raid" and "Raid" or "Overall"
    progressBar:SetMinMaxValues(0, totalSlots > 0 and totalSlots or 16)
    progressBar:SetValue(bisCount)
    progressText:SetText(string.format("BiS Progress (%s): %d/%d equipped", sourceLabel, bisCount, totalSlots > 0 and totalSlots or 16))
end

-- ============================================================
-- TOGGLE / SHOW
-- ============================================================

local initialized = false

local function InitOnce()
    if initialized then return end
    initialized = true
    CreateCrestBars()
end

function ns.ToggleOverview()
    InitOnce()
    if overviewFrame:IsShown() then
        overviewFrame:Hide()
    else
        overviewFrame:Show()
        RefreshOverview()
    end
end

overviewFrame:SetScript("OnShow", function()
    InitOnce()
    RefreshOverview()
end)

overviewFrame:SetScript("OnSizeChanged", function()
    if initialized then
        LayoutColumns()
    end
end)

-- Refresh on gear change
overviewFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
overviewFrame:RegisterEvent("CURRENCY_DISPLAY_UPDATE")
overviewFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
overviewFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_ENTERING_WORLD" then
        local db = GetOverviewDB()
        if db.point then
            overviewFrame:ClearAllPoints()
            overviewFrame:SetPoint(db.point[1], UIParent, db.point[2], db.point[3], db.point[4])
        end
        overviewFrame:SetSize(db.width, db.height)
    end
    if self:IsShown() then
        RefreshOverview()
    end
end)
