-- ADHDBiS: Best in Slot gear, enchants, gems, consumables & talents for any WoW class
-- =============================================================================

local addonName, ns = ...

-- SavedVariables (initialized before use)
ADHDBiSDB = ADHDBiSDB or {}

local defaults = {
    windowPoint = { "CENTER", nil, "CENTER", 0, 0 },
    windowWidth = 620,
    windowHeight = 520,
}

-- ============================================================
-- UTILITY: GetDB (defined first to avoid forward-reference bugs)
-- ============================================================

local function GetDB()
    for k, v in pairs(defaults) do
        if ADHDBiSDB[k] == nil then
            ADHDBiSDB[k] = v
        end
    end
    return ADHDBiSDB
end

-- ============================================================
-- CONSTANTS
-- ============================================================

local MIN_WIDTH = 380
local MIN_HEIGHT = 350
local ROW_HEIGHT = 18
local EPIC_COLOR = "|cFFA335EE"
local GRAY_COLOR = "|cFF888888"
local GREEN_DOT = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14:14|t"
local RED_DOT   = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:14:14|t"

-- List View constants (Gear tab)
local LIST_ICON_SIZE = 42
local LIST_ROW_HEIGHT = 52
local LIST_ROW_PADDING = 2
local LIST_BORDER_SIZE = 2
local LIST_COL_GAP = 4

local TAB_LIST  = { "Gear", "Trinkets", "Enchants+Gems", "Consumables", "Talents", "Vault" }

-- Raid difficulty ID to human-readable name
local DIFFICULTY_NAMES = {
    [17] = "LFR",
    [14] = "Normal",
    [15] = "Heroic",
    [16] = "Mythic",
}

-- Grid constants
local GRID_ICON_SIZE = 40
local GRID_CELL_WIDTH = 54
local GRID_CELL_HEIGHT = 76
local GRID_PADDING = 4
local GRID_BORDER_SIZE = 2

-- All WoW classes and their specs (for dropdown menus)
local CLASS_SPECS = {
    ["Death Knight"]  = { "Blood", "Frost", "Unholy" },
    ["Demon Hunter"]  = { "Devourer", "Havoc", "Vengeance" },
    ["Druid"]         = { "Balance", "Feral", "Guardian", "Restoration" },
    ["Evoker"]        = { "Augmentation", "Devastation", "Preservation" },
    ["Hunter"]        = { "Beast Mastery", "Marksmanship", "Survival" },
    ["Mage"]          = { "Arcane", "Fire", "Frost" },
    ["Monk"]          = { "Brewmaster", "Mistweaver", "Windwalker" },
    ["Paladin"]       = { "Holy", "Protection", "Retribution" },
    ["Priest"]        = { "Discipline", "Holy", "Shadow" },
    ["Rogue"]         = { "Assassination", "Outlaw", "Subtlety" },
    ["Shaman"]        = { "Elemental", "Enhancement", "Restoration" },
    ["Warlock"]       = { "Affliction", "Demonology", "Destruction" },
    ["Warrior"]       = { "Arms", "Fury", "Protection" },
}
local CLASS_ORDER = {
    "Death Knight", "Demon Hunter", "Druid", "Evoker", "Hunter", "Mage",
    "Monk", "Paladin", "Priest", "Rogue", "Shaman", "Warlock", "Warrior",
}

-- Slot name -> inventory slot ID for GetInventoryItemID
local SLOT_IDS = {
    Head = 1, Neck = 2, Shoulders = 3, Back = 15,
    Chest = 5, Wrist = 9, Hands = 10, Waist = 6,
    Legs = 7, Feet = 8, Finger1 = 11, Finger2 = 12,
    Trinket1 = 13, Trinket2 = 14, Weapon = 16, OffHand = 17,
}

-- Short slot labels for grid display
local SHORT_SLOT = {
    Head = "Head", Neck = "Neck", Shoulders = "Shld", Back = "Back",
    Chest = "Chest", Wrist = "Wrist", Hands = "Hands", Waist = "Waist",
    Legs = "Legs", Feet = "Feet", Finger1 = "Ring1", Finger2 = "Ring2",
    Trinket1 = "Trk1", Trinket2 = "Trk2", Weapon = "Wep", OffHand = "OH",
}

-- Trinket source lookup: find source from gear lists by itemID
local function FindTrinketSource(itemID)
    if not itemID or not ADHDBiS_Data then return nil end
    local playerClass = UnitClass("player")
    if not playerClass or not ADHDBiS_Data.classes or not ADHDBiS_Data.classes[playerClass] then return nil end
    for specName, sources in pairs(ADHDBiS_Data.classes[playerClass]) do
        if type(sources) ~= "table" then break end
        for sourceName, data in pairs(sources) do
            if type(data) == "table" and data.gear then
                for _, listType in ipairs({"mythicplus", "raid"}) do
                    if data.gear[listType] then
                        for _, item in ipairs(data.gear[listType]) do
                            if item.itemID == itemID and item.source then
                                return item.source
                            end
                        end
                    end
                end
            end
        end
    end
    return nil
end

-- Trinket ranking tier colors
local TIER_COLORS = {
    S = "|cFFFF8000",  -- Orange (legendary)
    A = "|cFFA335EE",  -- Purple (epic)
    B = "|cFF0070DD",  -- Blue (rare)
    C = "|cFF1EFF00",  -- Green (uncommon)
    D = "|cFF9D9D9D",  -- Gray (poor)
}
local TIER_ORDER = { "S", "A", "B", "C", "D" }

-- ============================================================
-- ITEM HELPERS
-- ============================================================

local function GetItemIcon(itemID)
    if not itemID then return "Interface\\Icons\\INV_Misc_QuestionMark" end
    local _, _, _, _, icon = GetItemInfoInstant(itemID)
    return icon or "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- ilvl cache: keyed by "itemID:bonusIDs" -> effective ilvl number
local ilvlCache = {}
local ilvlPendingItems = {} -- items we've requested but haven't got data for yet

-- Item name/quality cache: itemID -> { name, quality, color }
local itemInfoCache = {}
local QUALITY_COLORS = {
    [0] = "9D9D9D", -- Poor
    [1] = "FFFFFF", -- Common
    [2] = "1EFF00", -- Uncommon
    [3] = "0070DD", -- Rare
    [4] = "A335EE", -- Epic
    [5] = "FF8000", -- Legendary
    [6] = "E6CC80", -- Artifact
    [7] = "00CCFF", -- Heirloom
}

local function GetCachedItemInfo(itemID)
    if not itemID then return nil, nil, "A335EE" end
    if itemInfoCache[itemID] then
        local c = itemInfoCache[itemID]
        return c.name, c.quality, c.color
    end
    local name, _, quality = C_Item.GetItemInfo(itemID)
    if name then
        local color = QUALITY_COLORS[quality] or "A335EE"
        itemInfoCache[itemID] = { name = name, quality = quality, color = color }
        return name, quality, color
    end
    -- Not cached yet, request async load
    C_Item.RequestLoadItemDataByID(itemID)
    return nil, nil, "A335EE"
end

-- Bag scanner cache: itemID -> { inBag=bool, bagIlvl=number }
local bagBiSCache = {}
local bagCacheDirty = true

-- BiS lookup table: itemID -> { class, spec, source, slot, gearSource }
-- Built once when data loads, used by tooltip hook
local bisLookup = {}

local function BuildBiSLookup()
    wipe(bisLookup)
    if not ADHDBiS_Data or not ADHDBiS_Data.classes then return end
    for className, classData in pairs(ADHDBiS_Data.classes) do
        for specName, specSources in pairs(classData) do
            for sourceName, sourceData in pairs(specSources) do
                if type(sourceData) == "table" and sourceData.gear then
                    for _, gearType in ipairs({"overall", "raid", "mythicplus"}) do
                        local gearList = sourceData.gear[gearType]
                        if gearList then
                            for _, item in ipairs(gearList) do
                                if item.itemID then
                                    if not bisLookup[item.itemID] then
                                        bisLookup[item.itemID] = {}
                                    end
                                    bisLookup[item.itemID][#bisLookup[item.itemID] + 1] = {
                                        class = className,
                                        spec = specName,
                                        source = sourceName,
                                        slot = item.slot,
                                        gearSource = gearType,
                                        ilvl = item.ilvl,
                                    }
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

local function BuildItemString(itemID, bonusIDs)
    if not itemID or itemID == 0 then return nil end
    local itemStr = "item:" .. itemID
    if bonusIDs and bonusIDs ~= "" then
        local bonusList = {}
        for id in bonusIDs:gmatch("(%d+)") do
            bonusList[#bonusList + 1] = id
        end
        if #bonusList > 0 then
            -- item:ID:enchant:gem1:gem2:gem3:gem4:suffix:unique:level:spec:modifiers:context:craftQuality:numBonusIDs:b1:b2:...
            -- 13 empty fields between itemID and numBonusIDs (TWW format)
            itemStr = itemStr .. ":::::::::::::" .. #bonusList .. ":" .. table.concat(bonusList, ":")
        end
    end
    return itemStr
end

-- Minimum sane ilvl for current expansion gear (base ilvl without bonuses can be very low like 44)
local MIN_SANE_ILVL = 200

local function GetItemIlvl(itemID, bonusIDs, fallbackIlvl)
    if not itemID or itemID == 0 then return fallbackIlvl end

    local cacheKey = itemID .. ":" .. (bonusIDs or "")
    if ilvlCache[cacheKey] then
        return ilvlCache[cacheKey]
    end

    local itemStr = BuildItemString(itemID, bonusIDs)
    if not itemStr then return fallbackIlvl end

    -- Primary method: C_TooltipInfo.GetHyperlink correctly resolves bonus IDs
    -- GetDetailedItemLevelInfo / GetItemInfo return BASE ilvl for constructed item strings
    if C_TooltipInfo and C_TooltipInfo.GetHyperlink then
        local tooltipData = C_TooltipInfo.GetHyperlink(itemStr)
        if tooltipData and tooltipData.lines then
            for _, line in ipairs(tooltipData.lines) do
                if line.type == Enum.TooltipDataLineType.ItemLevel then
                    local ilvl = line.itemLevel
                    if not ilvl and line.leftText then
                        local num = line.leftText:match("(%d+)")
                        if num then ilvl = tonumber(num) end
                    end
                    if ilvl and ilvl >= MIN_SANE_ILVL then
                        ilvlCache[cacheKey] = ilvl
                        return ilvl
                    end
                end
            end
        end
    end

    -- Legacy fallback: GetDetailedItemLevelInfo (may work for cached items)
    local effectiveIlvl = GetDetailedItemLevelInfo and GetDetailedItemLevelInfo(itemStr)
    if effectiveIlvl and effectiveIlvl >= MIN_SANE_ILVL then
        ilvlCache[cacheKey] = effectiveIlvl
        return effectiveIlvl
    end

    -- Item not cached yet - request it for async load
    if not ilvlPendingItems[itemID] then
        ilvlPendingItems[itemID] = cacheKey
        C_Item.RequestLoadItemDataByID(itemID)
    end

    -- Use scraped ilvl as fallback (only if sane)
    if fallbackIlvl and fallbackIlvl >= MIN_SANE_ILVL then
        return fallbackIlvl
    end
    return fallbackIlvl
end

-- Parse source string into structured parts: { type, instance, boss }
-- "Vorasius in The Voidspire or Matrix Catalyst" -> { boss = "Vorasius", instance = "The Voidspire" }
-- "Crafted by Tailoring" -> { type = "Craft", instance = "Tailoring" }
-- "Matrix Catalyst" -> { type = "Catalyst" }
-- "Pit of Saron" -> { instance = "Pit of Saron" }
local function ParseSource(source)
    if not source or source == "" then return {} end
    local s = source:lower()

    if s:find("craft") or s:find("tailor") or s:find("leather") or s:find("black") or s:find("jewel")
        or s:find("enchant") or s:find("inscr") or s:find("engineer") or s:find("alchem") then
        local prof = source:match("[Bb]y (%w+)") or source
        return { type = "Craft", instance = prof }
    end
    if s:find("pvp") or s:find("arena") or s:find("battleground") then return { type = "PvP" } end
    if s:find("vault") or s:find("great") then return { type = "Vault" } end
    if s:find("delve") then return { type = "Delve", instance = source } end
    if s:find("world") or s:find("quest") then return { type = "World", instance = source } end
    if s:find("rep") or s:find("renown") then return { type = "Rep", instance = source } end

    -- Handle "or Matrix Catalyst" suffix
    local mainSource = source:gsub(" or Matrix Catalyst", ""):gsub(" or Catalyst", "")
    if mainSource == "Matrix Catalyst" or mainSource == "Catalyst" then
        return { type = "Catalyst" }
    end

    -- "Boss in Instance" pattern
    local boss, instance = mainSource:match("^(.+) in (.+)$")
    if boss and instance then
        return { boss = boss, instance = instance }
    end

    -- Standalone instance/location name
    return { instance = mainSource }
end

-- Format source for tooltip: "Raid: The Voidspire, Vorasius"
local function FormatSourceTooltip(source, gearSource)
    local p = ParseSource(source)
    if p.type == "Craft" then return "|cFFFFD100Craft:|r " .. (p.instance or "") end
    if p.type == "Catalyst" then return "|cFFFFD100Catalyst|r" end
    if p.type == "PvP" then return "|cFFFFD100PvP|r" end
    if p.type == "Vault" then return "|cFFFFD100Great Vault|r" end
    if p.type == "Delve" then return "|cFFFFD100Delve:|r " .. (p.instance or "") end
    if p.type == "World" then return "|cFFFFD100World:|r " .. (p.instance or "") end
    if p.type == "Rep" then return "|cFFFFD100Rep:|r " .. (p.instance or "") end

    -- Raid or M+ boss/instance
    local prefix = (gearSource == "mythicplus") and "|cFF00CCFFMythic+:|r " or "|cFFFF8800Raid:|r "
    if p.boss and p.instance then
        return prefix .. p.instance .. ", " .. p.boss
    elseif p.instance then
        return prefix .. p.instance
    end
    return source or ""
end

-- Shorten source for grid label
local function ShortSource(source)
    local p = ParseSource(source)
    if p.type then
        if p.type == "Catalyst" then return "Catalyst" end
        return p.type
    end
    -- Use instance name, shortened
    local inst = p.instance or ""
    inst = inst:gsub("^The ", "")
    if #inst > 8 then inst = inst:sub(1, 7) .. "." end
    return inst
end

-- ============================================================
-- STATE
-- ============================================================

local selectedClass = "Warlock"
local selectedSpec = "Demonology"
local selectedSource = "Icy Veins"
local selectedTab = 1
local selectedGearSource = "overall"
local contentRows = {}
local gridCells = {}

-- ============================================================
-- MAIN FRAME (resizable)
-- ============================================================

local mainFrame = CreateFrame("Frame", "ADHDBiSFrame", UIParent, "BackdropTemplate")
mainFrame:SetSize(defaults.windowWidth, defaults.windowHeight)
mainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
mainFrame:SetFrameStrata("HIGH")
mainFrame:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
})
mainFrame:SetBackdropColor(0.05, 0.05, 0.08, 0.92)
mainFrame:SetBackdropBorderColor(0.4, 0.2, 0.6, 0.9)
mainFrame:SetClampedToScreen(true)
mainFrame:EnableMouse(true)
mainFrame:SetMovable(true)
mainFrame:SetResizable(true)
mainFrame:SetResizeBounds(MIN_WIDTH, MIN_HEIGHT, 800, 900)
mainFrame:RegisterForDrag("LeftButton")
mainFrame:Hide()

mainFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
mainFrame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local db = GetDB()
    local point, _, relPoint, x, y = self:GetPoint()
    db.windowPoint = { point, nil, relPoint, x, y }
end)

-- Resize handle (bottom-right corner)
local resizeHandle = CreateFrame("Button", nil, mainFrame)
resizeHandle:SetSize(16, 16)
resizeHandle:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -2, 2)
resizeHandle:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
resizeHandle:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
resizeHandle:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")

resizeHandle:SetScript("OnMouseDown", function()
    mainFrame:StartSizing("BOTTOMRIGHT")
end)
resizeHandle:SetScript("OnMouseUp", function()
    mainFrame:StopMovingOrSizing()
    local db = GetDB()
    db.windowWidth = mainFrame:GetWidth()
    db.windowHeight = mainFrame:GetHeight()
    ns.OnResize()
end)

-- ============================================================
-- TITLE BAR
-- ============================================================

local titleBar = CreateFrame("Frame", nil, mainFrame)
titleBar:SetHeight(24)
titleBar:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 6, -6)
titleBar:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -6, -6)

local titleText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
titleText:SetPoint("LEFT", titleBar, "LEFT", 2, 0)
titleText:SetText("|cFF9482C9ADHDBiS|r")

-- Close button (custom - UIPanelCloseButton causes taint in Midnight)
local closeBtn = CreateFrame("Button", nil, titleBar)
closeBtn:SetSize(22, 22)
closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", 4, 0)
local closeBtnText = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
closeBtnText:SetPoint("CENTER")
closeBtnText:SetText("|cFFFF4444X|r")
closeBtn:SetScript("OnClick", function() mainFrame:Hide() end)
closeBtn:SetScript("OnEnter", function() closeBtnText:SetText("|cFFFF8888X|r") end)
closeBtn:SetScript("OnLeave", function() closeBtnText:SetText("|cFFFF4444X|r") end)

-- Export button
local exportBtn = CreateFrame("Button", nil, titleBar)
exportBtn:SetSize(50, 18)
exportBtn:SetPoint("RIGHT", closeBtn, "LEFT", -4, 0)
local exportBg = exportBtn:CreateTexture(nil, "BACKGROUND")
exportBg:SetAllPoints()
exportBg:SetColorTexture(0.3, 0.2, 0.5, 0.7)
local exportText = exportBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
exportText:SetPoint("CENTER")
exportText:SetText("Export")

-- ============================================================
-- CONTROLS ROW (class, spec, source in one horizontal row)
-- ============================================================

local controlBar = CreateFrame("Frame", nil, mainFrame)
controlBar:SetHeight(26)
controlBar:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 0, -2)
controlBar:SetPoint("RIGHT", mainFrame, "RIGHT", -8, 0)

-- Simple text button dropdown helper
local function CreateSimpleDropdown(parent, width, labelText, anchor, anchorTo, xOff, yOff)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(width, 22)
    frame:SetPoint(anchor, anchorTo, xOff, yOff)

    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.12, 0.12, 0.18, 0.9)

    local border = frame:CreateTexture(nil, "BORDER")
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetColorTexture(0.3, 0.2, 0.5, 0.6)

    local lbl = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("LEFT", 6, 0)
    lbl:SetPoint("RIGHT", -14, 0)
    lbl:SetJustifyH("LEFT")
    lbl:SetWordWrap(false)
    lbl:SetText(labelText)
    frame.label = lbl

    local arrow = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    arrow:SetPoint("RIGHT", -4, 0)
    arrow:SetText("|cFF888888v|r")

    return frame
end

-- Class button
local classBtn = CreateSimpleDropdown(controlBar, 110, selectedClass, "LEFT", controlBar, "LEFT", 0, 0)
-- Spec button
local specBtn = CreateSimpleDropdown(controlBar, 110, selectedSpec, "LEFT", classBtn, "RIGHT", 4, 0)
-- Source button (may be hidden)
local sourceBtn = CreateSimpleDropdown(controlBar, 90, selectedSource, "LEFT", specBtn, "RIGHT", 4, 0)

-- Custom dropdown menu (no UIDropDownMenuTemplate - causes taint in Midnight)
local dropMenuFrame = CreateFrame("Frame", "ADHDBiSCustomDrop", UIParent, "BackdropTemplate")
dropMenuFrame:SetFrameStrata("FULLSCREEN_DIALOG")
dropMenuFrame:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
})
dropMenuFrame:SetBackdropColor(0.08, 0.08, 0.12, 0.95)
dropMenuFrame:SetBackdropBorderColor(0.4, 0.2, 0.6, 0.9)
dropMenuFrame:EnableMouse(true)
dropMenuFrame:Hide()
dropMenuFrame.buttons = {}

dropMenuFrame:SetScript("OnShow", function(self)
    self:RegisterEvent("GLOBAL_MOUSE_DOWN")
end)
dropMenuFrame:SetScript("OnHide", function(self)
    self:UnregisterEvent("GLOBAL_MOUSE_DOWN")
end)
dropMenuFrame:SetScript("OnEvent", function(self, event)
    if event == "GLOBAL_MOUSE_DOWN" then
        if not self:IsMouseOver() then
            self:Hide()
        end
    end
end)

local function ShowDropdown(anchorFrame, items, currentValue, callback)
    -- Hide/recycle old buttons
    for _, btn in ipairs(dropMenuFrame.buttons) do
        btn:Hide()
    end

    local ITEM_HEIGHT = 20
    local ITEM_WIDTH = anchorFrame:GetWidth()
    if ITEM_WIDTH < 100 then ITEM_WIDTH = 100 end

    for i, item in ipairs(items) do
        local btn = dropMenuFrame.buttons[i]
        if not btn then
            btn = CreateFrame("Button", nil, dropMenuFrame)
            btn:SetHeight(ITEM_HEIGHT)

            local hl = btn:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(0.4, 0.2, 0.6, 0.4)

            local text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            text:SetPoint("LEFT", 8, 0)
            text:SetPoint("RIGHT", -8, 0)
            text:SetJustifyH("LEFT")
            btn.text = text

            local check = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            check:SetPoint("RIGHT", -4, 0)
            btn.check = check

            dropMenuFrame.buttons[i] = btn
        end

        btn:SetPoint("TOPLEFT", dropMenuFrame, "TOPLEFT", 4, -(4 + (i - 1) * ITEM_HEIGHT))
        btn:SetPoint("RIGHT", dropMenuFrame, "RIGHT", -4, 0)
        btn.text:SetText(item)
        btn.check:SetText(item == currentValue and "|cFF00FF00>|r" or "")
        btn:SetScript("OnClick", function()
            dropMenuFrame:Hide()
            callback(item)
        end)
        btn:Show()
    end

    dropMenuFrame:SetSize(ITEM_WIDTH + 8, #items * ITEM_HEIGHT + 8)
    dropMenuFrame:ClearAllPoints()
    dropMenuFrame:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, -2)
    dropMenuFrame:Show()
end

classBtn:EnableMouse(true)
classBtn:SetScript("OnMouseDown", function(self)
    ShowDropdown(self, CLASS_ORDER, selectedClass, function(val)
        selectedClass = val
        classBtn.label:SetText(val)
        -- Update spec
        local specs = CLASS_SPECS[selectedClass] or {}
        local validSpec = false
        for _, s in ipairs(specs) do
            if s == selectedSpec then validSpec = true break end
        end
        if not validSpec and #specs > 0 then
            selectedSpec = specs[1]
        end
        specBtn.label:SetText(selectedSpec)
        ns.RefreshContent()
    end)
end)

specBtn:EnableMouse(true)
specBtn:SetScript("OnMouseDown", function(self)
    ShowDropdown(self, CLASS_SPECS[selectedClass] or {}, selectedSpec, function(val)
        selectedSpec = val
        specBtn.label:SetText(val)
        ns.RefreshContent()
    end)
end)

sourceBtn:EnableMouse(true)
sourceBtn:SetScript("OnMouseDown", function(self)
    local allSources = {"Icy Veins", "Wowhead"}
    ShowDropdown(self, allSources, selectedSource, function(val)
        selectedSource = val
        sourceBtn.label:SetText(val)
        ns.RefreshContent()
    end)
end)

-- ============================================================
-- TAB BAR
-- ============================================================

local tabButtons = {}
local tabBar = CreateFrame("Frame", nil, mainFrame)
tabBar:SetHeight(22)
tabBar:SetPoint("TOPLEFT", controlBar, "BOTTOMLEFT", 0, -2)
tabBar:SetPoint("RIGHT", mainFrame, "RIGHT", -8, 0)

for i, tabName in ipairs(TAB_LIST) do
    local btn = CreateFrame("Button", nil, tabBar)
    btn:SetHeight(20)

    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("CENTER")
    label:SetText(tabName)
    btn.label = label

    btn:SetWidth(label:GetStringWidth() + 12)

    if i == 1 then
        btn:SetPoint("LEFT", tabBar, "LEFT", 0, 0)
    else
        btn:SetPoint("LEFT", tabButtons[i - 1], "RIGHT", 2, 0)
    end

    local underline = btn:CreateTexture(nil, "ARTWORK")
    underline:SetHeight(2)
    underline:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
    underline:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
    underline:SetColorTexture(0.58, 0.51, 0.79, 1)
    underline:Hide()
    btn.underline = underline

    btn:SetScript("OnClick", function()
        selectedTab = i
        ns.RefreshContent()
    end)

    tabButtons[i] = btn
end

-- ============================================================
-- GEAR SUB-BUTTONS (Raid / M+)
-- ============================================================

local gearToggleFrame = CreateFrame("Frame", nil, mainFrame)
gearToggleFrame:SetHeight(20)
gearToggleFrame:SetPoint("TOPLEFT", tabBar, "BOTTOMLEFT", 0, -2)
gearToggleFrame:SetPoint("RIGHT", mainFrame, "RIGHT", -8, 0)
gearToggleFrame:Hide()

local function CreateGearToggle(label, source, anchor)
    local btn = CreateFrame("Button", nil, gearToggleFrame)
    btn:SetSize(50, 18)
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
    btn:SetScript("OnClick", function()
        selectedGearSource = source
        ns.RefreshContent()
    end)
    return btn
end

local overallBtn = CreateGearToggle("Overall", "overall", nil)
local raidBtn = CreateGearToggle("Raid", "raid", overallBtn)
local mplusBtn = CreateGearToggle("M+", "mythicplus", raidBtn)

-- ============================================================
-- SCROLL FRAME
-- ============================================================

local scrollFrame = CreateFrame("ScrollFrame", "ADHDBiSScrollFrame", mainFrame, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", gearToggleFrame, "BOTTOMLEFT", 0, -4)
scrollFrame:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -28, 24)

local scrollChild = CreateFrame("Frame", nil, scrollFrame)
scrollChild:SetHeight(1)
scrollFrame:SetScrollChild(scrollChild)

-- ============================================================
-- DATA VERSION FOOTER
-- ============================================================

local versionText = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
versionText:SetPoint("BOTTOMLEFT", mainFrame, "BOTTOMLEFT", 8, 6)
versionText:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -20, 6)
versionText:SetJustifyH("LEFT")
versionText:SetTextColor(0.5, 0.5, 0.5, 1)

local function GetSourceTimestamp()
    -- Find sourceLastModified for current class/spec/source
    if not ADHDBiS_Data or not ADHDBiS_Data.classes then return nil end
    local playerClass = UnitClass("player")
    local specIndex = GetSpecialization()
    if not playerClass or not specIndex then return nil end
    local _, specName = GetSpecializationInfo(specIndex)
    if not specName then return nil end
    local classData = ADHDBiS_Data.classes[playerClass]
    if not classData or not classData[specName] then return nil end
    local sourceData = classData[specName][selectedSource]
    if not sourceData then return nil end
    -- Parse HTTP date like "Wed, 25 Mar 2026 22:00:02 GMT" into short format
    local lastMod = sourceData.sourceLastModified
    if lastMod and lastMod ~= "" then
        local day, mon, year = lastMod:match("(%d+) (%a+) (%d+)")
        if day and mon and year then
            return day .. " " .. mon .. " " .. year
        end
        return lastMod
    end
    return sourceData.scrapedAt and sourceData.scrapedAt:match("^([^T]+)") or nil
end

local function UpdateVersionText()
    if ADHDBiS_Data then
        local info = (ADHDBiS_Data.version or "?") .. " | " .. selectedSource
        if ADHDBiS_Data.classes then
            local count = 0
            for _ in pairs(ADHDBiS_Data.classes) do count = count + 1 end
            info = count .. " classes | " .. info
        end
        local srcTime = GetSourceTimestamp()
        if srcTime then
            info = info .. " | src: " .. srcTime
        end
        versionText:SetText(info)
    else
        versionText:SetText("No data - run ADHDBiS Updater")
    end
end

-- ============================================================
-- RESIZE HANDLER
-- ============================================================

function ns.OnResize()
    local w = mainFrame:GetWidth()
    scrollChild:SetWidth(w - 42)
    if mainFrame:IsShown() then
        ns.RefreshContent()
    end
end

-- ============================================================
-- GRID CELL POOL
-- ============================================================

local function GetGridCell(index)
    if gridCells[index] then
        gridCells[index]:Show()
        return gridCells[index]
    end

    local cell = CreateFrame("Button", nil, scrollChild)
    cell:SetSize(GRID_CELL_WIDTH, GRID_CELL_HEIGHT)
    cell:RegisterForClicks("LeftButtonUp")
    cell:EnableMouse(true)

    -- Border background (slightly larger than icon, behind it)
    local borderTex = cell:CreateTexture(nil, "BACKGROUND")
    borderTex:SetSize(GRID_ICON_SIZE + GRID_BORDER_SIZE * 2, GRID_ICON_SIZE + GRID_BORDER_SIZE * 2)
    borderTex:SetPoint("TOP", cell, "TOP", 0, 0)
    borderTex:SetColorTexture(1, 0, 0, 1) -- default red
    cell.borderTex = borderTex

    -- Icon texture
    local icon = cell:CreateTexture(nil, "ARTWORK")
    icon:SetSize(GRID_ICON_SIZE, GRID_ICON_SIZE)
    icon:SetPoint("CENTER", borderTex, "CENTER", 0, 0)
    cell.icon = icon

    -- Slot label below icon
    local label = cell:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOP", borderTex, "BOTTOM", 0, -1)
    label:SetWidth(GRID_CELL_WIDTH)
    label:SetJustifyH("CENTER")
    label:SetWordWrap(false)
    cell.label = label

    -- Source label below slot (smaller, gray)
    local sourceLabel = cell:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sourceLabel:SetPoint("TOP", label, "BOTTOM", 0, 0)
    sourceLabel:SetWidth(GRID_CELL_WIDTH)
    sourceLabel:SetJustifyH("CENTER")
    sourceLabel:SetWordWrap(false)
    sourceLabel:SetTextColor(0.55, 0.55, 0.55, 1)
    cell.sourceLabel = sourceLabel

    -- Wishlist star overlay (top-right of icon)
    local wishlistStar = cell:CreateTexture(nil, "OVERLAY")
    wishlistStar:SetSize(22, 22)
    wishlistStar:SetPoint("TOPRIGHT", borderTex, "TOPRIGHT", 5, 5)
    wishlistStar:SetAtlas("PetJournal-FavoritesIcon")
    wishlistStar:Hide()
    cell.wishlistStar = wishlistStar

    -- Highlight on hover
    local highlight = cell:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints(borderTex)
    highlight:SetColorTexture(1, 1, 1, 0.2)

    -- Tooltip: native WoW tooltip with gear comparison + ilvl override
    cell:SetScript("OnEnter", function(self)
        if self.itemID then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local itemStr = BuildItemString(self.itemID, self.bonusIDs) or ("item:" .. self.itemID)
            GameTooltip:SetHyperlink(itemStr)
            -- Override ilvl text with correct value (WoW client shows base ilvl for constructed items)
            local correctIlvl = GetItemIlvl(self.itemID, self.bonusIDs, self.displayIlvl)
            if correctIlvl and correctIlvl >= MIN_SANE_ILVL then
                for i = 2, GameTooltip:NumLines() do
                    local line = _G["GameTooltipTextLeft" .. i]
                    if line then
                        local text = line:GetText()
                        if text and text:match(ITEM_LEVEL:gsub("%%d", "%%d+")) then
                            line:SetText(ITEM_LEVEL:format(correctIlvl))
                            break
                        end
                    end
                end
            end
            if self.fullSource and self.fullSource ~= "" then
                GameTooltip:AddLine(" ")
                local formatted = FormatSourceTooltip(self.fullSource, self.gearSource or selectedGearSource)
                GameTooltip:AddLine("Source: " .. formatted, 1, 1, 1, true)
            end
            GameTooltip:AddLine(" ")
            if ADHDBiS_LootDB and ADHDBiS_LootDB.wishlist and ADHDBiS_LootDB.wishlist[self.itemID] then
                GameTooltip:AddLine("|cFFFFD100Wishlisted|r", 1, 0.82, 0)
            end
            GameTooltip:AddLine("|cFF888888Click: Guide | Shift+Click: Link | RClick: Wishlist | Shift+RClick: Wowhead|r", 0.5, 0.5, 0.5, true)
            GameTooltip:Show()
        end
    end)
    cell:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Click handlers
    cell:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    cell:SetScript("OnClick", function(self, button)
        if not self.itemID then return end

        if button == "RightButton" and not IsShiftKeyDown() then
            -- Right Click: toggle wishlist
            if not ADHDBiS_LootDB then ADHDBiS_LootDB = {} end
            if not ADHDBiS_LootDB.wishlist then ADHDBiS_LootDB.wishlist = {} end
            if ADHDBiS_LootDB.wishlist[self.itemID] then
                ADHDBiS_LootDB.wishlist[self.itemID] = nil
                self.wishlistStar:Hide()
                print("|cFF9482C9ADHDBiS:|r Removed from wishlist.")
            else
                ADHDBiS_LootDB.wishlist[self.itemID] = true
                self.wishlistStar:Show()
                print("|cFF9482C9ADHDBiS:|r Added to wishlist!")
            end
            return
        end

        if button == "LeftButton" and IsShiftKeyDown() then
            -- Shift+Left Click: link item to chat / insert into Auctionator etc.
            local _, link = C_Item.GetItemInfo(self.itemID)
            if link then
                if not HandleModifiedItemClick(link) then
                    ChatEdit_InsertLink(link)
                end
            end

        elseif button == "RightButton" and IsShiftKeyDown() then
            -- Shift+Right Click: copy Wowhead URL
            local url = "https://www.wowhead.com/item=" .. self.itemID
            if not ns.wowheadCopyBox then
                local box = CreateFrame("EditBox", "ADHDBiSWowheadBox", mainFrame, "InputBoxTemplate")
                box:SetSize(mainFrame:GetWidth() - 40, 24)
                box:SetPoint("TOP", mainFrame, "BOTTOM", 0, -4)
                box:SetAutoFocus(true)
                box:SetFontObject("ChatFontNormal")
                box:SetScript("OnEscapePressed", function(self) self:Hide() end)
                box:SetScript("OnEnterPressed", function(self) self:Hide() end)
                box:Hide()
                ns.wowheadCopyBox = box
            end
            ns.wowheadCopyBox:SetText(url)
            ns.wowheadCopyBox:Show()
            ns.wowheadCopyBox:HighlightText()
            ns.wowheadCopyBox:SetFocus()
            print("|cFF9482C9ADHDBiS:|r Wowhead URL ready - Ctrl+C to copy, Escape to close.")

        elseif button == "LeftButton" and not IsShiftKeyDown() then
            -- Left Click: open Adventure Guide via item link
            local itemID = self.itemID
            local _, link = C_Item.GetItemInfo(itemID)
            if link then
                -- SetItemRef opens the item popup which has "View in Adventure Guide" button
                local refStr = link:match("|H(item:[^|]+)|h")
                if refStr then
                    SetItemRef(refStr, link, "LeftButton")
                end
            else
                -- Item not in cache yet, print link to chat
                print("|cFF9482C9ADHDBiS:|r " .. (self.fullSource or "Item " .. itemID))
            end
        end
    end)

    gridCells[index] = cell
    return cell
end

local function HideAllGridCells()
    for _, cell in ipairs(gridCells) do
        cell:Hide()
        cell.itemID = nil
        cell.fullSource = nil
        cell.gearSource = nil
        if cell.wishlistStar then cell.wishlistStar:Hide() end
    end
end

local function LayoutGridCells(count, yOffset)
    yOffset = yOffset or 0
    local frameWidth = scrollChild:GetWidth()
    local cols = math.floor(frameWidth / (GRID_CELL_WIDTH + GRID_PADDING))
    if cols < 1 then cols = 1 end

    for i = 1, count do
        local cell = gridCells[i]
        if cell and cell:IsShown() then
            local row = math.floor((i - 1) / cols)
            local col = (i - 1) % cols
            cell:ClearAllPoints()
            cell:SetPoint("TOPLEFT", scrollChild, "TOPLEFT",
                col * (GRID_CELL_WIDTH + GRID_PADDING),
                -(row * (GRID_CELL_HEIGHT + GRID_PADDING)) - yOffset)
        end
    end

    local rows = math.ceil(count / cols)
    return rows * (GRID_CELL_HEIGHT + GRID_PADDING) + yOffset
end

-- ============================================================
-- BAG SCANNER (event-driven, cached)
-- ============================================================

local function ScanBags()
    wipe(bagBiSCache)
    for bag = 0, 4 do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                local id = info.itemID
                if not bagBiSCache[id] then
                    bagBiSCache[id] = { inBag = true }
                end
                -- Get ilvl from the actual bag item
                local itemLink = C_Container.GetContainerItemLink(bag, slot)
                if itemLink then
                    local ilvl = GetDetailedItemLevelInfo(itemLink)
                    if ilvl and ilvl > 0 then
                        local existing = bagBiSCache[id].bagIlvl
                        if not existing or ilvl > existing then
                            bagBiSCache[id].bagIlvl = ilvl
                        end
                    end
                end
            end
        end
    end
    bagCacheDirty = false
end

-- Get the 4-state status for an item: "equipped_bis", "equipped_low", "in_bag", "missing"
local function GetItemBiSState(itemID, slot, bisIlvl, bonusIDs)
    if not itemID then return "missing" end

    -- Check equipped
    local slotID = SLOT_IDS[slot]
    if slotID then
        local equippedID = GetInventoryItemID("player", slotID)
        if equippedID == itemID then
            -- Check ilvl match
            if bisIlvl and bisIlvl >= MIN_SANE_ILVL then
                local equippedLink = GetInventoryItemLink("player", slotID)
                if equippedLink then
                    local equippedIlvl = GetDetailedItemLevelInfo(equippedLink)
                    if equippedIlvl and equippedIlvl >= bisIlvl then
                        return "equipped_bis"  -- green checkmark
                    else
                        return "equipped_low"  -- yellow arrow (upgradeable)
                    end
                end
            end
            return "equipped_bis"  -- can't verify ilvl, assume OK
        end
    end

    -- Check bag
    if bagCacheDirty then ScanBags() end
    if bagBiSCache[itemID] and bagBiSCache[itemID].inBag then
        return "in_bag"  -- blue bag icon
    end

    return "missing"  -- red X
end

-- ============================================================
-- LIST ROW POOL (for Gear tab list view)
-- ============================================================

local listRows = {}

local function GetListRow(index)
    if listRows[index] then
        listRows[index]:Show()
        return listRows[index]
    end

    local row = CreateFrame("Button", nil, scrollChild)
    row:SetHeight(LIST_ROW_HEIGHT)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:EnableMouse(true)

    -- Row background (alternating, subtle)
    local rowBg = row:CreateTexture(nil, "BACKGROUND")
    rowBg:SetAllPoints()
    rowBg:SetColorTexture(0.1, 0.1, 0.15, 0.3)
    row.rowBg = rowBg

    -- Icon border (status-colored)
    local borderTex = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    borderTex:SetSize(LIST_ICON_SIZE + LIST_BORDER_SIZE * 2, LIST_ICON_SIZE + LIST_BORDER_SIZE * 2)
    borderTex:SetPoint("LEFT", row, "LEFT", 4, 0)
    borderTex:SetColorTexture(0.8, 0, 0, 1)
    row.borderTex = borderTex

    -- Icon
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(LIST_ICON_SIZE, LIST_ICON_SIZE)
    icon:SetPoint("CENTER", borderTex, "CENTER", 0, 0)
    row.icon = icon

    -- Status icon (overlays top-right of item icon)
    local statusIcon = row:CreateTexture(nil, "OVERLAY")
    statusIcon:SetSize(16, 16)
    statusIcon:SetPoint("TOPRIGHT", borderTex, "TOPRIGHT", 3, 3)
    row.statusIcon = statusIcon

    -- Item name (large, colored by quality)
    local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameText:SetPoint("TOPLEFT", borderTex, "TOPRIGHT", 6, -4)
    nameText:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    nameText:SetJustifyH("LEFT")
    nameText:SetWordWrap(false)
    row.nameText = nameText

    -- Drop source text (smaller, gray) - includes slot info
    local sourceText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sourceText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -2)
    sourceText:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    sourceText:SetJustifyH("LEFT")
    sourceText:SetWordWrap(false)
    sourceText:SetTextColor(0.6, 0.6, 0.6, 1)
    row.sourceText = sourceText

    -- Wishlist star
    local wishlistStar = row:CreateTexture(nil, "OVERLAY")
    wishlistStar:SetSize(18, 18)
    wishlistStar:SetPoint("TOPRIGHT", borderTex, "TOPRIGHT", -1, -1)
    wishlistStar:SetAtlas("PetJournal-FavoritesIcon")
    wishlistStar:Hide()
    row.wishlistStar = wishlistStar

    -- Highlight
    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.06)

    -- Tooltip
    row:SetScript("OnEnter", function(self)
        if self.itemID then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local itemStr = BuildItemString(self.itemID, self.bonusIDs) or ("item:" .. self.itemID)
            GameTooltip:SetHyperlink(itemStr)
            local correctIlvl = GetItemIlvl(self.itemID, self.bonusIDs, self.displayIlvl)
            if correctIlvl and correctIlvl >= MIN_SANE_ILVL then
                for i = 2, GameTooltip:NumLines() do
                    local line = _G["GameTooltipTextLeft" .. i]
                    if line then
                        local text = line:GetText()
                        if text and text:match(ITEM_LEVEL:gsub("%%d", "%%d+")) then
                            line:SetText(ITEM_LEVEL:format(correctIlvl))
                            break
                        end
                    end
                end
            end
            if self.fullSource and self.fullSource ~= "" then
                GameTooltip:AddLine(" ")
                local formatted = FormatSourceTooltip(self.fullSource, self.gearSource or selectedGearSource)
                GameTooltip:AddLine("Source: " .. formatted, 1, 1, 1, true)
            end
            GameTooltip:AddLine(" ")
            if ADHDBiS_LootDB and ADHDBiS_LootDB.wishlist and ADHDBiS_LootDB.wishlist[self.itemID] then
                GameTooltip:AddLine("|cFFFFD100Wishlisted|r", 1, 0.82, 0)
            end
            GameTooltip:AddLine("|cFF888888Click: Guide | Shift+Click: Link | RClick: Wishlist|r", 0.5, 0.5, 0.5, true)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Click handlers (same as grid cells)
    row:SetScript("OnClick", function(self, button)
        if not self.itemID then return end
        if button == "RightButton" and not IsShiftKeyDown() then
            if not ADHDBiS_LootDB then ADHDBiS_LootDB = {} end
            if not ADHDBiS_LootDB.wishlist then ADHDBiS_LootDB.wishlist = {} end
            if ADHDBiS_LootDB.wishlist[self.itemID] then
                ADHDBiS_LootDB.wishlist[self.itemID] = nil
                self.wishlistStar:Hide()
                print("|cFF9482C9ADHDBiS:|r Removed from wishlist.")
            else
                ADHDBiS_LootDB.wishlist[self.itemID] = true
                self.wishlistStar:Show()
                print("|cFF9482C9ADHDBiS:|r Added to wishlist!")
            end
            return
        end
        if button == "LeftButton" and IsShiftKeyDown() then
            local _, link = C_Item.GetItemInfo(self.itemID)
            if link then
                if not HandleModifiedItemClick(link) then
                    ChatEdit_InsertLink(link)
                end
            end
        elseif button == "RightButton" and IsShiftKeyDown() then
            local url = "https://www.wowhead.com/item=" .. self.itemID
            if not ns.wowheadCopyBox then
                local box = CreateFrame("EditBox", "ADHDBiSWowheadBox", mainFrame, "InputBoxTemplate")
                box:SetSize(mainFrame:GetWidth() - 40, 24)
                box:SetPoint("TOP", mainFrame, "BOTTOM", 0, -4)
                box:SetAutoFocus(true)
                box:SetFontObject("ChatFontNormal")
                box:SetScript("OnEscapePressed", function(s) s:Hide() end)
                box:SetScript("OnEnterPressed", function(s) s:Hide() end)
                box:Hide()
                ns.wowheadCopyBox = box
            end
            ns.wowheadCopyBox:SetText(url)
            ns.wowheadCopyBox:Show()
            ns.wowheadCopyBox:HighlightText()
            ns.wowheadCopyBox:SetFocus()
        elseif button == "LeftButton" and not IsShiftKeyDown() then
            local _, link = C_Item.GetItemInfo(self.itemID)
            if link then
                local refStr = link:match("|H(item:[^|]+)|h")
                if refStr then SetItemRef(refStr, link, "LeftButton") end
            end
        end
    end)

    listRows[index] = row
    return row
end

local function HideAllListRows()
    for _, row in ipairs(listRows) do
        row:Hide()
        row.itemID = nil
        row.fullSource = nil
        row.gearSource = nil
    end
end

-- ============================================================
-- SECTION HEADER POOL (for grid tabs with section headers)
-- ============================================================

local sectionHeaders = {}

local function GetSectionHeader(index)
    if sectionHeaders[index] then
        sectionHeaders[index]:Show()
        return sectionHeaders[index]
    end

    local hdr = CreateFrame("Frame", nil, scrollChild)
    hdr:SetHeight(18)

    local text = hdr:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("LEFT", hdr, "LEFT", 2, 0)
    text:SetPoint("RIGHT", hdr, "RIGHT", -2, 0)
    text:SetJustifyH("LEFT")
    hdr.text = text

    sectionHeaders[index] = hdr
    return hdr
end

local function HideAllSectionHeaders()
    for _, hdr in ipairs(sectionHeaders) do
        hdr:Hide()
    end
end

-- ============================================================
-- ROW POOL (kept for Talents tab)
-- ============================================================

local function GetRow(index)
    if contentRows[index] then
        contentRows[index]:Show()
        return contentRows[index]
    end

    local row = CreateFrame("Button", nil, scrollChild)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
    row:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)
    row:RegisterForClicks("LeftButtonUp")
    row:EnableMouse(true)

    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.05)

    local text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("LEFT", row, "LEFT", 2, 0)
    text:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    row.text = text

    row:SetScript("OnEnter", function(self)
        if self.itemID then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink("item:" .. self.itemID)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)

    row:SetScript("OnClick", function(self, button)
        if self.itemID and IsShiftKeyDown() then
            local itemName, link = C_Item.GetItemInfo(self.itemID)
            local focusedBox = GetCurrentKeyBoardFocus()
            if focusedBox then
                if link and focusedBox == ChatFrame1EditBox then
                    ChatEdit_InsertLink(link)
                elseif itemName then
                    focusedBox:Insert(itemName)
                elseif link then
                    ChatEdit_InsertLink(link)
                end
            else
                if link then ChatEdit_InsertLink(link) end
            end
        end
        if self.copyFunc then self.copyFunc() end
    end)

    contentRows[index] = row
    return row
end

local function HideAllRows()
    for _, row in ipairs(contentRows) do
        row:Hide()
        row.itemID = nil
        row.copyFunc = nil
    end
end

local function HideAll()
    HideAllRows()
    HideAllGridCells()
    HideAllListRows()
    HideAllSectionHeaders()
end

-- ============================================================
-- CONTENT RENDERERS
-- ============================================================

local function GetSpecData()
    if not ADHDBiS_Data then return nil end
    if ADHDBiS_Data.classes then
        local classData = ADHDBiS_Data.classes[selectedClass]
        if not classData then return nil end
        local specData = classData[selectedSpec]
        if not specData then return nil end
        if specData[selectedSource] then
            return specData[selectedSource]
        end
        for _, data in pairs(specData) do
            if type(data) == "table" and data.gear then return data end
        end
    end
    if ADHDBiS_Data.specs then
        return ADHDBiS_Data.specs[selectedSpec]
    end
    return nil
end

local function GetAvailableSources()
    local sources = {}
    if not ADHDBiS_Data then return sources end
    if ADHDBiS_Data.classes then
        local classData = ADHDBiS_Data.classes[selectedClass]
        if not classData then return sources end
        local specData = classData[selectedSpec]
        if not specData then return sources end
        for sourceName, data in pairs(specData) do
            if type(data) == "table" and data.gear then
                table.insert(sources, sourceName)
            end
        end
        table.sort(sources)
    elseif ADHDBiS_Data.specs then
        if ADHDBiS_Data.specs[selectedSpec] then
            table.insert(sources, ADHDBiS_Data.source or "Unknown")
        end
    end
    return sources
end
ns.GetAvailableSources = GetAvailableSources

-- GEAR TAB (List View - two columns with icon + name + drop source)
local function RenderGear()
    local specData = GetSpecData()
    if not specData or not specData.gear then return end
    local gearList = specData.gear[selectedGearSource]
    -- Fallback: if overall doesn't exist yet, use raid
    if not gearList and selectedGearSource == "overall" then
        gearList = specData.gear["raid"]
    end
    if not gearList then return end

    -- Ensure bag cache is fresh
    if bagCacheDirty then ScanBags() end

    local frameWidth = scrollChild:GetWidth()
    local useTwoCols = frameWidth >= 400
    local colWidth = useTwoCols and math.floor((frameWidth - LIST_COL_GAP) / 2) or frameWidth

    local rowIndex = 0
    local yOffset = 0

    -- BiS progress counter
    local totalItems = #gearList
    local equippedCount = 0

    for i, item in ipairs(gearList) do
        rowIndex = rowIndex + 1
        local row = GetListRow(rowIndex)

        -- Alternating row background
        if rowIndex % 2 == 0 then
            row.rowBg:SetColorTexture(0.12, 0.1, 0.18, 0.3)
        else
            row.rowBg:SetColorTexture(0.08, 0.08, 0.12, 0.15)
        end

        -- Icon
        row.icon:SetTexture(GetItemIcon(item.itemID))

        -- 4-state status
        local bisIlvl = GetItemIlvl(item.itemID, item.bonusIDs, (item.ilvl and item.ilvl > 0) and item.ilvl or nil)
        local state = GetItemBiSState(item.itemID, item.slot, bisIlvl, item.bonusIDs)

        if state == "equipped_bis" then
            row.borderTex:SetColorTexture(0, 0.7, 0, 1)  -- green
            row.icon:SetAlpha(0.5)
            row.icon:SetDesaturated(true)
            row.statusIcon:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
            row.statusIcon:SetVertexColor(1, 1, 1, 1)
            row.statusIcon:Show()
            equippedCount = equippedCount + 1
        elseif state == "equipped_low" then
            row.borderTex:SetColorTexture(0.9, 0.7, 0, 1)  -- yellow
            row.icon:SetAlpha(0.7)
            row.icon:SetDesaturated(false)
            row.statusIcon:SetTexture("Interface\\RaidFrame\\ReadyCheck-Waiting")
            row.statusIcon:SetVertexColor(1, 1, 1, 1)
            row.statusIcon:Show()
            equippedCount = equippedCount + 1
        elseif state == "in_bag" then
            row.borderTex:SetColorTexture(0, 0.4, 0.8, 1)  -- blue
            row.icon:SetAlpha(1)
            row.icon:SetDesaturated(false)
            row.statusIcon:SetTexture("Interface\\Icons\\INV_Misc_Bag_08")
            row.statusIcon:SetVertexColor(1, 1, 1, 1)
            row.statusIcon:Show()
        else -- missing
            row.borderTex:SetColorTexture(0.6, 0, 0, 1)  -- red
            row.icon:SetAlpha(1)
            row.icon:SetDesaturated(false)
            row.statusIcon:SetTexture("Interface\\RaidFrame\\ReadyCheck-NotReady")
            row.statusIcon:SetVertexColor(1, 1, 1, 1)
            row.statusIcon:Show()
        end

        -- Item name (colored by quality)
        local itemName, _, qualColor = GetCachedItemInfo(item.itemID)
        if itemName then
            row.nameText:SetText("|cFF" .. qualColor .. itemName .. "|r")
        else
            -- Fallback: use name from data file
            row.nameText:SetText("|cFFA335EE" .. (item.name or "Loading...") .. "|r")
        end

        -- Drop source (with slot prefix)
        local sourceStr = item.source or ""
        local slotName = item.slot or ""
        if sourceStr ~= "" then
            row.sourceText:SetText(slotName .. ": " .. sourceStr)
        else
            row.sourceText:SetText(slotName)
        end

        -- Data for tooltip/clicks
        row.fullSource = sourceStr
        row.gearSource = selectedGearSource
        row.itemID = item.itemID
        row.bonusIDs = item.bonusIDs or ""
        row.displayIlvl = bisIlvl

        -- Wishlist star
        if ADHDBiS_LootDB and ADHDBiS_LootDB.wishlist and ADHDBiS_LootDB.wishlist[item.itemID] then
            row.wishlistStar:Show()
        else
            row.wishlistStar:Hide()
        end

        -- Position: two-column layout
        if useTwoCols then
            local col = (i - 1) % 2
            local visualRow = math.floor((i - 1) / 2)
            row:ClearAllPoints()
            row:SetWidth(colWidth)
            row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT",
                col * (colWidth + LIST_COL_GAP),
                -(visualRow * (LIST_ROW_HEIGHT + LIST_ROW_PADDING)))
        else
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -(yOffset))
            row:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)
            yOffset = yOffset + LIST_ROW_HEIGHT + LIST_ROW_PADDING
        end
    end

    -- Calculate total height
    local totalHeight
    if useTwoCols then
        local numVisualRows = math.ceil(#gearList / 2)
        totalHeight = numVisualRows * (LIST_ROW_HEIGHT + LIST_ROW_PADDING)
    else
        totalHeight = yOffset
    end

    -- Progress bar at bottom
    if totalItems > 0 then
        local pct = math.floor((equippedCount / totalItems) * 100)
        local progressStr = equippedCount .. "/" .. totalItems .. " equipped (" .. pct .. "%)"
        local srcTime = GetSourceTimestamp()
        local verInfo = progressStr .. " | " .. (ADHDBiS_Data and ADHDBiS_Data.version or "?") .. " | " .. selectedSource
        if srcTime then verInfo = verInfo .. " | src: " .. srcTime end
        versionText:SetText(verInfo)
    end

    scrollChild:SetHeight(math.max(1, totalHeight))
end

-- TRINKETS TAB (Grid with tier sections)
local function RenderTrinketRankings()
    local specData = GetSpecData()
    if not specData or not specData.trinketRankings or #specData.trinketRankings == 0 then
        local row = GetRow(1)
        row.text:SetText("|cFFFFD100No trinket rankings available for this spec.|r")
        row.itemID = nil
        scrollChild:SetHeight(ROW_HEIGHT)
        return
    end

    -- Group trinkets by tier
    local byTier = {}
    for _, tr in ipairs(specData.trinketRankings) do
        if not byTier[tr.tier] then
            byTier[tr.tier] = {}
        end
        table.insert(byTier[tr.tier], tr)
    end

    -- Get equipped trinket IDs for highlighting
    local equippedTrinket1 = GetInventoryItemID("player", 13)
    local equippedTrinket2 = GetInventoryItemID("player", 14)

    local cellIndex = 0
    local sectionIdx = 0
    local yOffset = 0
    local frameWidth = scrollChild:GetWidth()
    local cols = math.floor(frameWidth / (GRID_CELL_WIDTH + GRID_PADDING))
    if cols < 1 then cols = 1 end

    for _, tier in ipairs(TIER_ORDER) do
        local trinkets = byTier[tier]
        if trinkets and #trinkets > 0 then
            -- Section header
            sectionIdx = sectionIdx + 1
            local hdr = GetSectionHeader(sectionIdx)
            local color = TIER_COLORS[tier] or "|cFFFFFFFF"
            hdr.text:SetText(color .. "-- " .. tier .. " Tier --|r")
            hdr:ClearAllPoints()
            hdr:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yOffset)
            hdr:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)
            yOffset = yOffset + 22

            -- Grid cells for this tier (manually positioned)
            local tierCellCount = 0
            for _, tr in ipairs(trinkets) do
                cellIndex = cellIndex + 1
                tierCellCount = tierCellCount + 1
                local cell = GetGridCell(cellIndex)

                -- Icon
                cell.icon:SetTexture(GetItemIcon(tr.itemID))

                -- Equipped check (trinket slot 13 or 14)
                local isEquipped = (equippedTrinket1 and equippedTrinket1 == tr.itemID) or
                                   (equippedTrinket2 and equippedTrinket2 == tr.itemID)
                if isEquipped then
                    cell.borderTex:SetColorTexture(0, 0.8, 0, 1) -- green
                    cell.icon:SetAlpha(0.35)
                    cell.icon:SetDesaturated(true)
                else
                    cell.borderTex:SetColorTexture(0.8, 0, 0, 1) -- red
                    cell.icon:SetAlpha(1)
                    cell.icon:SetDesaturated(false)
                end

                -- Tier label + source below icon
                local tierColor = TIER_COLORS[tier] or "|cFFFFFFFF"
                local trinketSource = FindTrinketSource(tr.itemID)
                cell.label:SetText(tierColor .. tier .. " Tier|r")
                if trinketSource then
                    -- Truncate long source for display
                    local shortSource = trinketSource
                    if #shortSource > 25 then
                        shortSource = shortSource:sub(1, 23) .. ".."
                    end
                    cell.sourceLabel:SetText("|cFF888888" .. shortSource .. "|r")
                    cell.fullSource = trinketSource
                else
                    cell.sourceLabel:SetText("")
                    cell.fullSource = ""
                end
                cell.gearSource = trinketSource
                cell.itemID = tr.itemID
                cell.bonusIDs = ""

                -- Wishlist star
                if ADHDBiS_LootDB and ADHDBiS_LootDB.wishlist and ADHDBiS_LootDB.wishlist[tr.itemID] then
                    cell.wishlistStar:Show()
                else
                    cell.wishlistStar:Hide()
                end

                -- Manual grid positioning within this tier section
                local localIdx = tierCellCount - 1
                local row = math.floor(localIdx / cols)
                local col = localIdx % cols
                cell:ClearAllPoints()
                cell:SetPoint("TOPLEFT", scrollChild, "TOPLEFT",
                    col * (GRID_CELL_WIDTH + GRID_PADDING),
                    -(row * (GRID_CELL_HEIGHT + GRID_PADDING)) - yOffset)
            end

            -- Advance yOffset past this tier's grid
            local tierRows = math.ceil(tierCellCount / cols)
            yOffset = yOffset + tierRows * (GRID_CELL_HEIGHT + GRID_PADDING)
        end
    end

    scrollChild:SetHeight(math.max(1, yOffset))
end

-- Enchant/gem detection helpers
local ENCHANT_SLOT_MAP = {
    Head = 1, Helm = 1, Shoulders = 3, Back = 15, Cloak = 15,
    Chest = 5, Wrist = 9, Legs = 7, Feet = 8,
    Finger1 = 11, Finger2 = 12, Rings = 11,
    Weapon = 16,
}

local function HasEnchantOnSlot(enchSlot, enchName)
    local slotsToCheck = {}
    local slotLower = enchSlot and enchSlot:lower() or ""
    if slotLower == "finger1" or slotLower == "rings" or slotLower == "finger" or slotLower == "ring" then
        slotsToCheck = {11, 12}
    else
        local slotID = ENCHANT_SLOT_MAP[enchSlot] or SLOT_IDS[enchSlot]
        if slotID then slotsToCheck = {slotID} end
    end
    for _, slotID in ipairs(slotsToCheck) do
        local link = GetInventoryItemLink("player", slotID)
        if link then
            local tooltipData = C_TooltipInfo.GetInventoryItem("player", slotID)
            if tooltipData and tooltipData.lines then
                for _, line in ipairs(tooltipData.lines) do
                    local text = line.leftText or ""
                    if enchName and text:find(enchName:gsub("Enchant %w+ %- ", ""), 1, true) then
                        return true
                    end
                end
            end
            local enchantField = link:match("|Hitem:%d+:(%d+)")
            if enchantField and tonumber(enchantField) and tonumber(enchantField) > 0 then
                return true
            end
        end
    end
    return false
end

local function HasGemEquipped(gemItemID)
    local gemSlots = {1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17}
    for _, slotID in ipairs(gemSlots) do
        local link = GetInventoryItemLink("player", slotID)
        if link then
            local parts = {link:match("|Hitem:(%d+):(%d+):(%d+):(%d+):(%d+):(%d+)")}
            for i = 3, #parts do
                if tonumber(parts[i]) == gemItemID then return true end
            end
        end
    end
    return false
end

-- ENCHANTS + GEMS TAB (Grid with section headers)
local function RenderEnchantsGems()
    local specData = GetSpecData()
    if not specData then return end

    local cellIndex = 0
    local headerIndex = 0
    local yOffset = 0
    local frameWidth = scrollChild:GetWidth()
    local cols = math.floor(frameWidth / (GRID_CELL_WIDTH + GRID_PADDING))
    if cols < 1 then cols = 1 end

    -- Enchants section
    if specData.enchants and #specData.enchants > 0 then
        headerIndex = headerIndex + 1
        local hdr = GetSectionHeader(headerIndex)
        hdr.text:SetText("|cFFFFD100-- Enchants --|r")
        hdr:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yOffset)
        hdr:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)
        yOffset = yOffset + 20

        local sectionStart = cellIndex
        for _, ench in ipairs(specData.enchants) do
            cellIndex = cellIndex + 1
            local cell = GetGridCell(cellIndex)
            cell.icon:SetTexture(GetItemIcon(ench.itemID))

            local hasIt = HasEnchantOnSlot(ench.slot, ench.name)
            if hasIt then
                cell.borderTex:SetColorTexture(0, 0.8, 0, 1)
                cell.icon:SetAlpha(0.35)
                cell.icon:SetDesaturated(true)
            else
                cell.borderTex:SetColorTexture(0.4, 0.2, 0.6, 0.8)
                cell.icon:SetAlpha(1)
                cell.icon:SetDesaturated(false)
            end

            cell.label:SetText(ench.slot or "")
            cell.sourceLabel:SetText("")
            cell.fullSource = ""
            cell.itemID = ench.itemID

            -- Position this cell
            local idx = cellIndex - sectionStart
            local row = math.floor((idx - 1) / cols)
            local col = (idx - 1) % cols
            cell:ClearAllPoints()
            cell:SetPoint("TOPLEFT", scrollChild, "TOPLEFT",
                col * (GRID_CELL_WIDTH + GRID_PADDING),
                -(row * (GRID_CELL_HEIGHT + GRID_PADDING)) - yOffset)
        end

        local enchCount = cellIndex - sectionStart
        local enchRows = math.ceil(enchCount / cols)
        yOffset = yOffset + enchRows * (GRID_CELL_HEIGHT + GRID_PADDING) + 4
    end

    -- Gems section
    if specData.gems and #specData.gems > 0 then
        headerIndex = headerIndex + 1
        local hdr = GetSectionHeader(headerIndex)
        hdr.text:SetText("|cFFFFD100-- Gems --|r")
        hdr:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yOffset)
        hdr:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)
        yOffset = yOffset + 20

        local sectionStart = cellIndex
        for _, gem in ipairs(specData.gems) do
            cellIndex = cellIndex + 1
            local cell = GetGridCell(cellIndex)
            cell.icon:SetTexture(GetItemIcon(gem.itemID))

            local hasGem = HasGemEquipped(gem.itemID)
            if hasGem then
                cell.borderTex:SetColorTexture(0, 0.8, 0, 1)
                cell.icon:SetAlpha(0.35)
                cell.icon:SetDesaturated(true)
            else
                cell.borderTex:SetColorTexture(0.4, 0.2, 0.6, 0.8)
                cell.icon:SetAlpha(1)
                cell.icon:SetDesaturated(false)
            end

            local noteStr = (gem.note and gem.note ~= "") and gem.note or "Gem"
            cell.label:SetText(noteStr)
            cell.sourceLabel:SetText("")
            cell.fullSource = ""
            cell.itemID = gem.itemID

            local idx = cellIndex - sectionStart
            local row = math.floor((idx - 1) / cols)
            local col = (idx - 1) % cols
            cell:ClearAllPoints()
            cell:SetPoint("TOPLEFT", scrollChild, "TOPLEFT",
                col * (GRID_CELL_WIDTH + GRID_PADDING),
                -(row * (GRID_CELL_HEIGHT + GRID_PADDING)) - yOffset)
        end

        local gemCount = cellIndex - sectionStart
        local gemRows = math.ceil(gemCount / cols)
        yOffset = yOffset + gemRows * (GRID_CELL_HEIGHT + GRID_PADDING)
    end

    scrollChild:SetHeight(math.max(1, yOffset))
end

-- CONSUMABLES TAB (Grid with section headers)
local function RenderConsumables()
    local specData = GetSpecData()
    if not specData or not specData.consumables then return end

    local grouped = {}
    local order = {}
    for _, cons in ipairs(specData.consumables) do
        if not grouped[cons.type] then
            grouped[cons.type] = {}
            table.insert(order, cons.type)
        end
        table.insert(grouped[cons.type], cons)
    end

    local cellIndex = 0
    local headerIndex = 0
    local yOffset = 0
    local frameWidth = scrollChild:GetWidth()
    local cols = math.floor(frameWidth / (GRID_CELL_WIDTH + GRID_PADDING))
    if cols < 1 then cols = 1 end

    for _, ctype in ipairs(order) do
        headerIndex = headerIndex + 1
        local hdr = GetSectionHeader(headerIndex)
        hdr.text:SetText("|cFFFFD100-- " .. ctype .. " --|r")
        hdr:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yOffset)
        hdr:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)
        yOffset = yOffset + 20

        local sectionStart = cellIndex
        for _, cons in ipairs(grouped[ctype]) do
            cellIndex = cellIndex + 1
            local cell = GetGridCell(cellIndex)
            cell.icon:SetTexture(GetItemIcon(cons.itemID))

            -- Consumables don't have equipped check, use neutral border
            cell.borderTex:SetColorTexture(0.4, 0.2, 0.6, 0.8) -- purple/neutral
            cell.icon:SetAlpha(1)
            cell.icon:SetDesaturated(false)

            cell.label:SetText(cons.type or "")
            cell.sourceLabel:SetText("")
            cell.fullSource = ""
            cell.itemID = cons.itemID

            local idx = cellIndex - sectionStart
            local row = math.floor((idx - 1) / cols)
            local col = (idx - 1) % cols
            cell:ClearAllPoints()
            cell:SetPoint("TOPLEFT", scrollChild, "TOPLEFT",
                col * (GRID_CELL_WIDTH + GRID_PADDING),
                -(row * (GRID_CELL_HEIGHT + GRID_PADDING)) - yOffset)
        end

        local secCount = cellIndex - sectionStart
        local secRows = math.ceil(secCount / cols)
        yOffset = yOffset + secRows * (GRID_CELL_HEIGHT + GRID_PADDING) + 4
    end

    scrollChild:SetHeight(math.max(1, yOffset))
end

-- TALENTS TAB (text rows - unchanged)
local function RenderTalents()
    local specData = GetSpecData()
    if not specData or not specData.talents then return end

    local contextLabels = {
        raid = "Raid", mythicplus = "M+", delves = "Delves",
        pvp = "PvP", general = "General",
    }

    local rowIndex = 0
    for _, talent in ipairs(specData.talents) do
        rowIndex = rowIndex + 1
        local nameRow = GetRow(rowIndex)
        local contextLabel = contextLabels[talent.context] or talent.context
        nameRow.text:SetText(string.format("|cFFFFD100%s|r  %s(%s)|r", talent.name, GRAY_COLOR, contextLabel))
        nameRow.itemID = nil

        rowIndex = rowIndex + 1
        local codeRow = GetRow(rowIndex)
        local codeShort = #talent.code > 30 and (talent.code:sub(1, 30) .. "...") or talent.code
        codeRow.text:SetText("|cFF69CCF0[Click to Copy]|r " .. GRAY_COLOR .. codeShort .. "|r")
        codeRow.itemID = nil

        local talentCode = talent.code
        codeRow.copyFunc = function()
            if not ns.copyBox then
                local box = CreateFrame("EditBox", "ADHDBiSCopyBox", mainFrame, "InputBoxTemplate")
                box:SetSize(mainFrame:GetWidth() - 40, 24)
                box:SetPoint("TOP", mainFrame, "BOTTOM", 0, -4)
                box:SetAutoFocus(true)
                box:SetFontObject("ChatFontNormal")
                box:SetScript("OnEscapePressed", function(self) self:Hide() end)
                box:SetScript("OnEnterPressed", function(self) self:Hide() end)
                box:Hide()
                ns.copyBox = box
            end
            ns.copyBox:SetText(talentCode)
            ns.copyBox:Show()
            ns.copyBox:HighlightText()
            ns.copyBox:SetFocus()
            print("|cFF9482C9ADHDBiS:|r Talent string ready - press Ctrl+C to copy, then Escape to close.")
        end

        rowIndex = rowIndex + 1
        local spacer = GetRow(rowIndex)
        spacer.text:SetText("")
        spacer.itemID = nil
    end

    scrollChild:SetHeight(math.max(1, rowIndex * ROW_HEIGHT))
end

-- VAULT TAB (Great Vault weekly progress)
local function RenderVault()
    if not C_WeeklyRewards then
        local row = GetRow(1)
        row.text:SetText("|cFFFF4444Weekly Vault data not available.|r")
        row.itemID = nil
        scrollChild:SetHeight(ROW_HEIGHT)
        return
    end

    local rowIndex = 0

    -- Check if vault is ready to claim
    if C_WeeklyRewards.CanClaimRewards() then
        rowIndex = rowIndex + 1
        local row = GetRow(rowIndex)
        row.text:SetText("|cFFFFD100>> Your Great Vault is ready to open! <<|r")
        row.itemID = nil
        rowIndex = rowIndex + 1
        local spacer = GetRow(rowIndex)
        spacer.text:SetText("")
        spacer.itemID = nil
    end

    -- Helper: get ilvl from vault reward item links (reads actual reward from API)
    local function GetRewardIlvl(activityID)
        if not activityID then return nil end
        local link = C_WeeklyRewards.GetExampleRewardItemHyperlinks(activityID)
        if link then
            local ilvl = GetDetailedItemLevelInfo(link)
            if ilvl and ilvl > 0 then return ilvl end
        end
        return nil
    end

    -- Helper: get human-readable level label
    local function GetLevelLabel(thresholdType, level)
        if not level or level == 0 then return "" end
        if thresholdType == Enum.WeeklyRewardChestThresholdType.Raid then
            return DIFFICULTY_NAMES[level] or ("Difficulty " .. level)
        elseif thresholdType == Enum.WeeklyRewardChestThresholdType.Activities then
            return "+" .. level
        elseif thresholdType == Enum.WeeklyRewardChestThresholdType.World then
            return "Tier " .. level
        end
        return tostring(level)
    end

    -- Helper: render one activity type
    local function RenderActivity(title, thresholdType)
        rowIndex = rowIndex + 1
        local hdr = GetRow(rowIndex)
        hdr.text:SetText("|cFFFFD100-- " .. title .. " --|r")
        hdr.itemID = nil

        local activities = C_WeeklyRewards.GetActivities(thresholdType)
        if not activities or #activities == 0 then
            rowIndex = rowIndex + 1
            local row = GetRow(rowIndex)
            row.text:SetText("  |cFF888888No data available|r")
            row.itemID = nil
            return
        end

        -- Sort by threshold ascending
        table.sort(activities, function(a, b) return a.threshold < b.threshold end)

        for i, activity in ipairs(activities) do
            rowIndex = rowIndex + 1
            local row = GetRow(rowIndex)

            local progress = activity.progress or 0
            local threshold = activity.threshold or 1
            local level = activity.level or 0
            local unlocked = progress >= threshold

            -- Progress bar (text-based)
            local barLen = 15
            local filled = math.min(barLen, math.floor((progress / threshold) * barLen))
            local bar = ""
            for j = 1, barLen do
                if j <= filled then
                    bar = bar .. "|cFF00FF00|r"
                else
                    bar = bar .. "|cFF333333-|r"
                end
            end

            -- Get actual ilvl from API reward data
            local ilvl = GetRewardIlvl(activity.id)
            local ilvlStr = ""
            if ilvl then
                if unlocked then
                    ilvlStr = " |cFF00FF00ilvl " .. ilvl .. "|r"
                else
                    ilvlStr = " |cFF888888ilvl " .. ilvl .. "|r"
                end
            end

            -- Level info (human-readable)
            local levelStr = ""
            if level > 0 then
                levelStr = " |cFF888888(" .. GetLevelLabel(thresholdType, level) .. ")|r"
            end

            -- Status
            local status
            if unlocked then
                status = "|cFF00FF00UNLOCKED|r"
            else
                status = "|cFFFFFFFF" .. progress .. "/" .. threshold .. "|r"
            end

            row.text:SetText("  Slot " .. i .. ": " .. bar .. " " .. status .. ilvlStr .. levelStr)
            row.itemID = nil
        end

        rowIndex = rowIndex + 1
        local spacer = GetRow(rowIndex)
        spacer.text:SetText("")
        spacer.itemID = nil
    end

    -- Render all 3 activity types
    RenderActivity("Raids", Enum.WeeklyRewardChestThresholdType.Raid)
    RenderActivity("Mythic+", Enum.WeeklyRewardChestThresholdType.Activities)
    RenderActivity("Delves", Enum.WeeklyRewardChestThresholdType.World)

    -- Tip at the bottom
    rowIndex = rowIndex + 1
    local tip = GetRow(rowIndex)
    tip.text:SetText("|cFF555555Vault resets weekly on Tuesday (US) / Wednesday (EU)|r")
    tip.itemID = nil

    scrollChild:SetHeight(math.max(1, rowIndex * ROW_HEIGHT))
end

-- ============================================================
-- EXPORT BUTTON OnClick
-- ============================================================

exportBtn:SetScript("OnClick", function()
    local specData = GetSpecData()
    if not specData then
        print("|cFF9482C9ADHDBiS:|r No data to export.")
        return
    end

    local lines = {}
    table.insert(lines, "=== " .. selectedClass .. " " .. selectedSpec .. " BiS (" .. selectedSource .. ") ===")
    table.insert(lines, "")

    local gearList = specData.gear and specData.gear[selectedGearSource]
    if gearList then
        local gsLabel = selectedGearSource == "raid" and "Raid" or (selectedGearSource == "mythicplus" and "M+" or "Overall")
        table.insert(lines, "-- " .. gsLabel .. " Gear --")
        for _, item in ipairs(gearList) do
            table.insert(lines, item.slot .. ": " .. item.name .. " (" .. item.source .. ")")
        end
        table.insert(lines, "")
    end

    if specData.enchants and #specData.enchants > 0 then
        table.insert(lines, "-- Enchants --")
        for _, ench in ipairs(specData.enchants) do
            table.insert(lines, ench.slot .. ": " .. ench.name)
        end
        table.insert(lines, "")
    end

    if specData.gems and #specData.gems > 0 then
        table.insert(lines, "-- Gems --")
        for _, gem in ipairs(specData.gems) do
            local note = (gem.note and gem.note ~= "") and (" (" .. gem.note .. ")") or ""
            table.insert(lines, gem.name .. note)
        end
        table.insert(lines, "")
    end

    if specData.consumables and #specData.consumables > 0 then
        table.insert(lines, "-- Consumables --")
        for _, cons in ipairs(specData.consumables) do
            table.insert(lines, cons.type .. ": " .. cons.name)
        end
    end

    local fullText = table.concat(lines, "\n")

    if not ns.exportFrame then
        local ef = CreateFrame("Frame", "ADHDBiSExportFrame", mainFrame, "BackdropTemplate")
        ef:SetSize(mainFrame:GetWidth() - 20, 200)
        ef:SetPoint("TOP", mainFrame, "BOTTOM", 0, -4)
        ef:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        ef:SetBackdropColor(0.05, 0.05, 0.08, 0.95)
        ef:SetBackdropBorderColor(0.4, 0.2, 0.6, 0.9)

        local sf = CreateFrame("ScrollFrame", "ADHDBiSExportScroll", ef, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", ef, "TOPLEFT", 8, -8)
        sf:SetPoint("BOTTOMRIGHT", ef, "BOTTOMRIGHT", -28, 8)

        local box = CreateFrame("EditBox", "ADHDBiSExportBox", sf)
        box:SetWidth(sf:GetWidth() or (mainFrame:GetWidth() - 56))
        box:SetAutoFocus(true)
        box:SetFontObject("ChatFontSmall")
        box:SetMultiLine(true)
        box:SetScript("OnEscapePressed", function() ef:Hide() end)
        sf:SetScrollChild(box)

        ef:Hide()
        ns.exportFrame = ef
        ns.exportBox = box
    end
    ns.exportBox:SetText(fullText)
    ns.exportFrame:Show()
    ns.exportBox:HighlightText()
    ns.exportBox:SetFocus()
    print("|cFF9482C9ADHDBiS:|r BiS list in export box. Press Ctrl+C, then Escape.")
end)

-- ============================================================
-- REFRESH CONTENT
-- ============================================================

function ns.RefreshContent()
    HideAll()

    -- Update scroll child width
    scrollChild:SetWidth(mainFrame:GetWidth() - 42)

    -- Check if data exists at all
    if selectedTab ~= 6 and (not ADHDBiS_Data or (not ADHDBiS_Data.classes and not ADHDBiS_Data.specs)) then
        -- No data - show setup message
        gearToggleFrame:Hide()
        scrollFrame:SetPoint("TOPLEFT", tabBar, "BOTTOMLEFT", 0, -4)
        local row = GetRow(1)
        row.text:SetText("")
        row.itemID = nil
        local row2 = GetRow(2)
        row2.text:SetText("|cFFFFD100No BiS data found.|r")
        row2.itemID = nil
        local row3 = GetRow(3)
        row3.text:SetText("")
        row3.itemID = nil
        local row4 = GetRow(4)
        row4.text:SetText("|cFFFFFFFFRun the ADHDBiS Updater companion app to")
        row4.itemID = nil
        local row5 = GetRow(5)
        row5.text:SetText("|cFFFFFFFFdownload BiS data for all classes.|r")
        row5.itemID = nil
        local row6 = GetRow(6)
        row6.text:SetText("")
        row6.itemID = nil
        local row7 = GetRow(7)
        row7.text:SetText("|cFF888888After updating, type /reload to refresh.|r")
        row7.itemID = nil
        scrollChild:SetHeight(7 * ROW_HEIGHT)
        UpdateVersionText()
        return
    end

    -- Update source button
    sourceBtn.label:SetText(selectedSource)
    -- Hide source selector on Vault tab (not relevant)
    if selectedTab == 6 then
        sourceBtn:Hide()
    else
        sourceBtn:Show()
    end

    -- Update tab highlights
    for i, btn in ipairs(tabButtons) do
        if i == selectedTab then
            btn.label:SetTextColor(1, 1, 1, 1)
            btn.underline:Show()
        else
            btn.label:SetTextColor(0.6, 0.6, 0.6, 1)
            btn.underline:Hide()
        end
    end

    -- Show/hide gear source toggle
    if selectedTab == 1 then
        gearToggleFrame:Show()
        local activeBg = {0.4, 0.2, 0.6, 0.7}
        local inactiveBg = {0.2, 0.2, 0.3, 0.6}
        overallBtn.bg:SetColorTexture(unpack(selectedGearSource == "overall" and activeBg or inactiveBg))
        raidBtn.bg:SetColorTexture(unpack(selectedGearSource == "raid" and activeBg or inactiveBg))
        mplusBtn.bg:SetColorTexture(unpack(selectedGearSource == "mythicplus" and activeBg or inactiveBg))
        scrollFrame:SetPoint("TOPLEFT", gearToggleFrame, "BOTTOMLEFT", 0, -4)
    else
        gearToggleFrame:Hide()
        scrollFrame:SetPoint("TOPLEFT", tabBar, "BOTTOMLEFT", 0, -4)
    end

    -- Render active tab
    if selectedTab == 1 then
        RenderGear()
    elseif selectedTab == 2 then
        RenderTrinketRankings()
    elseif selectedTab == 3 then
        RenderEnchantsGems()
    elseif selectedTab == 4 then
        RenderConsumables()
    elseif selectedTab == 5 then
        RenderTalents()
    elseif selectedTab == 6 then
        RenderVault()
    end

    scrollFrame:SetVerticalScroll(0)
    -- Gear tab sets its own footer with progress; other tabs use default
    if selectedTab ~= 1 then
        UpdateVersionText()
    end
end

-- ============================================================
-- TOGGLE PANEL
-- ============================================================

local function TogglePanel()
    if mainFrame:IsShown() then
        mainFrame:Hide()
    else
        mainFrame:Show()
        ns.OnResize()
        ns.RefreshContent()
    end
end

-- ============================================================
-- AUTO-DETECT SPEC
-- ============================================================

local function DetectSpec()
    local _, englishClass = UnitClass("player")
    if englishClass then
        local classMap = {
            DEATHKNIGHT = "Death Knight", DEMONHUNTER = "Demon Hunter",
            DRUID = "Druid", EVOKER = "Evoker", HUNTER = "Hunter",
            MAGE = "Mage", MONK = "Monk", PALADIN = "Paladin",
            PRIEST = "Priest", ROGUE = "Rogue", SHAMAN = "Shaman",
            WARLOCK = "Warlock", WARRIOR = "Warrior",
        }
        local className = classMap[englishClass]
        if className then
            selectedClass = className
            classBtn.label:SetText(className)
        end
    end

    local specIndex = GetSpecialization()
    if specIndex then
        local _, specName = GetSpecializationInfo(specIndex)
        if specName then
            selectedSpec = specName
            specBtn.label:SetText(specName)
        end
    end
end

-- ============================================================
-- EVENT HANDLING
-- ============================================================

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
eventFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")

-- Throttle refresh: avoid multiple refreshes in same frame
local refreshQueued = false
local function QueueRefresh()
    if refreshQueued then return end
    if not mainFrame:IsShown() then return end
    refreshQueued = true
    C_Timer.After(0.1, function()
        refreshQueued = false
        if mainFrame:IsShown() then
            ns.RefreshContent()
        end
    end)
end

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        local db = GetDB()
        local p = db.windowPoint
        if p then
            mainFrame:ClearAllPoints()
            mainFrame:SetPoint(p[1], UIParent, p[3], p[4], p[5])
        end
        mainFrame:SetSize(db.windowWidth or defaults.windowWidth, db.windowHeight or defaults.windowHeight)

        DetectSpec()
        BuildBiSLookup()
        bagCacheDirty = true

        -- Check if data is stale
        if ADHDBiS_Data and ADHDBiS_Data.version then
            local year, month, day = ADHDBiS_Data.version:match("(%d+)-(%d+)-(%d+)")
            if year then
                local dataTime = time({year=tonumber(year), month=tonumber(month), day=tonumber(day)})
                local daysDiff = math.floor((time() - dataTime) / 86400)
                if daysDiff > 7 then
                    print("|cFF9482C9ADHDBiS:|r Data is " .. daysDiff .. " days old. Consider running the updater.")
                end
            end
        end

        -- Check for new addon version
        if ADHDBiS_Data and ADHDBiS_Data.latestAddonVersion then
            local currentVer = C_AddOns.GetAddOnMetadata("ADHDBiS", "Version") or "0"
            local latestVer = ADHDBiS_Data.latestAddonVersion
            if latestVer ~= "" and currentVer ~= latestVer then
                -- Simple string comparison works for our X.Y.Z format when lengths match
                -- For safety, compare numerically
                local function verNum(v)
                    local major, minor, patch = v:match("(%d+)%.(%d+)%.(%d+)")
                    if not major then return 0 end
                    return tonumber(major) * 10000 + tonumber(minor) * 100 + tonumber(patch)
                end
                if verNum(latestVer) > verNum(currentVer) then
                    print("|cFF9482C9ADHDBiS:|r New version |cFF00FF00v" .. latestVer .. "|r available! You have v" .. currentVer .. ". Download from CurseForge or GitHub.")
                end
            end
        end

        -- Check if companion app was updated and data needs refresh
        if ADHDBiS_Data then
            local db = GetDB()
            local dataCompVer = ADHDBiS_Data.companionVersion -- nil if old companion app
            if not dataCompVer then
                -- Old companion app without version tracking - notify to update
                if not db.dismissedOldCompanion then
                    C_Timer.After(5, function()
                        print("|cFF9482C9ADHDBiS:|r |cFFFF8800Your Companion App is outdated.|r Please download the latest version from CurseForge or GitHub to get new features.")
                        local db2 = GetDB()
                        db2.dismissedOldCompanion = true
                    end)
                end
            elseif db.lastCompanionVersion and db.lastCompanionVersion ~= dataCompVer then
                -- Companion app was updated - notify user
                C_Timer.After(5, function()
                    if not ADHDBiSCompanionPopup then
                        local pop = CreateFrame("Frame", "ADHDBiSCompanionPopup", UIParent, "BackdropTemplate")
                        pop:SetSize(380, 120)
                        pop:SetPoint("CENTER", UIParent, "CENTER", 0, 150)
                        pop:SetFrameStrata("DIALOG")
                        pop:SetBackdrop({
                            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                            tile = true, tileSize = 16, edgeSize = 16,
                            insets = { left = 4, right = 4, top = 4, bottom = 4 },
                        })
                        pop:SetBackdropColor(0.06, 0.06, 0.1, 0.97)
                        pop:SetBackdropBorderColor(0.8, 0.5, 0.1, 0.9)
                        pop:EnableMouse(true)

                        local title = pop:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
                        title:SetPoint("TOPLEFT", 14, -12)
                        title:SetText("|cFFFFD100ADHDBiS Companion App Updated|r")

                        local body = pop:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                        body:SetPoint("TOPLEFT", 14, -36)
                        body:SetPoint("TOPRIGHT", -14, -36)
                        body:SetJustifyH("LEFT")
                        body:SetWordWrap(true)
                        body:SetText("A new Companion App (v" .. dataCompVer .. ") generated your BiS data.\n|cFFFF8800Please download the latest Companion App|r from CurseForge or GitHub to keep your data up to date.")

                        local okBtn = CreateFrame("Button", nil, pop, "UIPanelButtonTemplate")
                        okBtn:SetSize(80, 24)
                        okBtn:SetPoint("BOTTOMRIGHT", pop, "BOTTOMRIGHT", -10, 10)
                        okBtn:SetText("OK")
                        okBtn:SetScript("OnClick", function()
                            pop:Hide()
                            local db2 = GetDB()
                            db2.lastCompanionVersion = dataCompVer
                        end)
                        pop:Show()
                    end
                end)
            else
                db.lastCompanionVersion = dataCompVer
            end
        end

        if mainFrame:IsShown() then
            ns.OnResize()
            ns.RefreshContent()
        end

        -- Welcome popup (once per login, dismissable forever)
        if not db.hideSupportMsg then
            C_Timer.After(3, function()
                if not ns.welcomePopup then
                    local pop = CreateFrame("Frame", "ADHDBiSWelcome", UIParent, "BackdropTemplate")
                    pop:SetSize(340, 310)
                    pop:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
                    pop:SetFrameStrata("DIALOG")
                    pop:SetBackdrop({
                        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                        tile = true, tileSize = 16, edgeSize = 16,
                        insets = { left = 4, right = 4, top = 4, bottom = 4 },
                    })
                    pop:SetBackdropColor(0.05, 0.05, 0.1, 0.95)
                    pop:SetBackdropBorderColor(0.4, 0.2, 0.6, 0.9)
                    pop:EnableMouse(true)
                    pop:SetMovable(true)
                    pop:RegisterForDrag("LeftButton")
                    pop:SetScript("OnDragStart", function(self) self:StartMoving() end)
                    pop:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

                    -- Title
                    local title = pop:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
                    title:SetPoint("TOP", pop, "TOP", 0, -16)
                    title:SetText("|cFF9482C9ADHDBiS|r")

                    -- Subtitle
                    local sub = pop:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                    sub:SetPoint("TOP", title, "BOTTOM", 0, -4)
                    sub:SetText("|cFFBBBBBBBest in Slot & Loot Tracker|r")

                    -- Commands
                    local cmds = pop:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    cmds:SetPoint("TOP", sub, "BOTTOM", 0, -14)
                    cmds:SetWidth(300)
                    cmds:SetJustifyH("LEFT")
                    cmds:SetSpacing(3)
                    cmds:SetText(
                        "|cFFFFFFFF/adhd bis|r  |cFF888888- BiS gear panel|r\n" ..
                        "|cFFFFFFFF/adhd loot|r  |cFF888888- Loot tracker|r\n" ..
                        "|cFFFFFFFF/adhd loot new|r  |cFF888888- New session|r\n" ..
                        "|cFFFFFFFF/adhd loot help|r  |cFF888888- All commands|r\n\n" ..
                        "|cFF888888Or use the minimap button! (Shift+Drag to move)|r"
                    )

                    -- Separator
                    local sep = pop:CreateTexture(nil, "ARTWORK")
                    sep:SetHeight(1)
                    sep:SetPoint("LEFT", pop, "LEFT", 16, 0)
                    sep:SetPoint("RIGHT", pop, "RIGHT", -16, 0)
                    sep:SetPoint("TOP", cmds, "BOTTOM", 0, -10)
                    sep:SetColorTexture(0.3, 0.2, 0.5, 0.5)

                    -- Support text
                    local support = pop:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    support:SetPoint("TOP", sep, "BOTTOM", 0, -10)
                    support:SetWidth(300)
                    support:SetJustifyH("CENTER")
                    support:SetText(
                        "|cFFBBBBBBEnjoy the addon? Support development!|r\n" ..
                        "|cFFFFDD00buymeacoffee.com/nenadjokic|r\n" ..
                        "|cFF0070BApaypal.me/nenadjokicRS|r"
                    )

                    -- "Don't show again" button
                    local dismissBtn = CreateFrame("Button", nil, pop)
                    dismissBtn:SetSize(200, 28)
                    dismissBtn:SetPoint("BOTTOM", pop, "BOTTOM", 0, 40)
                    local dismissBg = dismissBtn:CreateTexture(nil, "BACKGROUND")
                    dismissBg:SetAllPoints()
                    dismissBg:SetColorTexture(0.3, 0.15, 0.15, 0.8)
                    local dismissTxt = dismissBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    dismissTxt:SetPoint("CENTER")
                    dismissTxt:SetText("|cFFFF8888Don't show me this again|r")
                    dismissBtn:SetScript("OnClick", function()
                        local d = GetDB()
                        d.hideSupportMsg = true
                        pop:Hide()
                        print("|cFF9482C9ADHDBiS:|r Welcome popup hidden permanently.")
                    end)
                    dismissBtn:SetScript("OnEnter", function() dismissTxt:SetText("|cFFFFAAAADon't show me this again|r") end)
                    dismissBtn:SetScript("OnLeave", function() dismissTxt:SetText("|cFFFF8888Don't show me this again|r") end)

                    -- Close button (X) to dismiss for this session only
                    local closeBtn = CreateFrame("Button", nil, pop)
                    closeBtn:SetSize(22, 22)
                    closeBtn:SetPoint("TOPRIGHT", pop, "TOPRIGHT", -6, -6)
                    local closeTxt = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                    closeTxt:SetPoint("CENTER")
                    closeTxt:SetText("|cFFFF4444X|r")
                    closeBtn:SetScript("OnClick", function() pop:Hide() end)
                    closeBtn:SetScript("OnEnter", function() closeTxt:SetText("|cFFFF8888X|r") end)
                    closeBtn:SetScript("OnLeave", function() closeTxt:SetText("|cFFFF4444X|r") end)

                    ns.welcomePopup = pop
                end
                ns.welcomePopup:Show()
            end)
        end

    elseif event == "ACTIVE_TALENT_GROUP_CHANGED" then
        DetectSpec()
        bagCacheDirty = true
        if mainFrame:IsShown() then ns.RefreshContent() end

    elseif event == "GET_ITEM_INFO_RECEIVED" then
        local itemID = ...
        if itemID then
            -- Update item info cache
            local name, _, quality = C_Item.GetItemInfo(itemID)
            if name then
                local color = QUALITY_COLORS[quality] or "A335EE"
                itemInfoCache[itemID] = { name = name, quality = quality, color = color }
            end
            -- Update ilvl cache
            if ilvlPendingItems[itemID] then
                local cacheKey = ilvlPendingItems[itemID]
                ilvlPendingItems[itemID] = nil
                ilvlCache[cacheKey] = nil
            end
            -- Throttled refresh if gear tab is showing
            if mainFrame:IsShown() and (selectedTab == 1 or selectedTab == 2) then
                QueueRefresh()
            end
        end

    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        bagCacheDirty = true
        QueueRefresh()

    elseif event == "BAG_UPDATE_DELAYED" then
        bagCacheDirty = true
        QueueRefresh()
    end
end)

-- ============================================================
-- MINIMAP BUTTON (parented to UIParent, not Minimap - avoids taint)
-- ============================================================

local minimapBtn = CreateFrame("Button", "ADHDBiSMinimapBtn", UIParent)
minimapBtn:SetSize(31, 31)
minimapBtn:SetFrameStrata("MEDIUM")
minimapBtn:SetFrameLevel(8)
minimapBtn:EnableMouse(true)
minimapBtn:SetMovable(true)
minimapBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")

-- Background (dark circle) - offset matches WoW standard minimap buttons
local mmBg = minimapBtn:CreateTexture(nil, "BACKGROUND")
mmBg:SetSize(21, 21)
mmBg:SetPoint("TOPLEFT", minimapBtn, "TOPLEFT", 7, -5)
mmBg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

-- Icon - same offset and size as background
local mmIcon = minimapBtn:CreateTexture(nil, "ARTWORK")
mmIcon:SetSize(17, 17)
mmIcon:SetPoint("TOPLEFT", minimapBtn, "TOPLEFT", 7, -5)
mmIcon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")

-- Border circle - anchored to TOPLEFT (NOT center - WoW tracking border is offset)
local mmBorder = minimapBtn:CreateTexture(nil, "OVERLAY")
mmBorder:SetSize(53, 53)
mmBorder:SetPoint("TOPLEFT", minimapBtn, "TOPLEFT", 0, 0)
mmBorder:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

-- Highlight on hover
local mmHighlight = minimapBtn:CreateTexture(nil, "HIGHLIGHT")
mmHighlight:SetSize(17, 17)
mmHighlight:SetPoint("TOPLEFT", minimapBtn, "TOPLEFT", 7, -5)
mmHighlight:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

-- Free-floating position (saved as x,y relative to UIParent center)
local mmDragging = false

local function RestoreMinimapPosition()
    local db = GetDB()
    minimapBtn:ClearAllPoints()
    if db.minimapX and db.minimapY then
        minimapBtn:SetPoint("CENTER", UIParent, "CENTER", db.minimapX, db.minimapY)
    else
        -- Default: near top-right of minimap
        local radius = (Minimap:GetWidth() / 2) + 16
        local x = math.cos(0.8) * radius
        local y = math.sin(0.8) * radius
        minimapBtn:SetPoint("CENTER", Minimap, "CENTER", x, y)
    end
end

minimapBtn:SetScript("OnMouseDown", function(self, button)
    if button == "LeftButton" and IsShiftKeyDown() then
        mmDragging = true
        self:StartMoving()
    end
end)

minimapBtn:SetScript("OnMouseUp", function(self, button)
    if mmDragging then
        mmDragging = false
        self:StopMovingOrSizing()
        -- Save position relative to UIParent center
        local cx, cy = self:GetCenter()
        local ux, uy = UIParent:GetCenter()
        local db = GetDB()
        db.minimapX = cx - ux
        db.minimapY = cy - uy
    end
end)

-- Tooltip
minimapBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("|cFF9482C9ADHDBiS|r")
    GameTooltip:AddLine("|cFFFFFFFFLeft-click:|r Toggle BiS Panel", 1, 1, 1)
    GameTooltip:AddLine("|cFFFFFFFFRight-click:|r Options Panel", 1, 1, 1)
    GameTooltip:AddLine("|cFFFFFFFFMiddle-click:|r Toggle LootRadar", 1, 1, 1)
    GameTooltip:AddLine("|cFF888888Shift+Drag anywhere to move|r", 0.5, 0.5, 0.5)
    GameTooltip:AddLine("|cFF888888/adhd minimap hide|r", 0.4, 0.4, 0.4)
    GameTooltip:Show()
end)
minimapBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- ============================================================
-- OPTIONS PANEL (right-click minimap)
-- ============================================================

local optPanel = CreateFrame("Frame", "ADHDBiSOptionsPanel", UIParent, "BackdropTemplate")
optPanel:SetSize(260, 420)
optPanel:SetFrameStrata("DIALOG")
optPanel:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
})
optPanel:SetBackdropColor(0.06, 0.06, 0.1, 0.97)
optPanel:SetBackdropBorderColor(0.4, 0.2, 0.6, 0.9)
optPanel:SetMovable(true)
optPanel:EnableMouse(true)
optPanel:RegisterForDrag("LeftButton")
optPanel:SetClampedToScreen(true)
optPanel:SetScript("OnDragStart", optPanel.StartMoving)
optPanel:SetScript("OnDragStop", optPanel.StopMovingOrSizing)
optPanel:Hide()

-- Title bar
local optTitleBg = optPanel:CreateTexture(nil, "ARTWORK")
optTitleBg:SetHeight(24)
optTitleBg:SetPoint("TOPLEFT", 4, -4)
optTitleBg:SetPoint("TOPRIGHT", -4, -4)
optTitleBg:SetColorTexture(0.15, 0.08, 0.25, 0.8)

local optTitle = optPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
optTitle:SetPoint("TOPLEFT", 12, -8)
optTitle:SetText("|cFF9482C9ADHDBiS|r Options")

-- Close button
local optClose = CreateFrame("Button", nil, optPanel)
optClose:SetSize(18, 18)
optClose:SetPoint("TOPRIGHT", -6, -6)
optClose:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
optClose:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
optClose:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight", "ADD")
optClose:SetScript("OnClick", function() optPanel:Hide() end)

-- Close on outside click
optPanel:SetScript("OnShow", function(self) self:RegisterEvent("GLOBAL_MOUSE_DOWN") end)
optPanel:SetScript("OnHide", function(self) self:UnregisterEvent("GLOBAL_MOUSE_DOWN") end)
optPanel:SetScript("OnEvent", function(self, event)
    if event == "GLOBAL_MOUSE_DOWN" and not self:IsMouseOver() then
        self:Hide()
    end
end)

-- Build options content
local OPT_Y = -32
local OPT_ROW = 22
local OPT_BTN_HEIGHT = 20

local function OptHeader(parent, text, yOff)
    local hdr = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hdr:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, yOff)
    hdr:SetText("|cFFFFD100" .. text .. "|r")
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, yOff - 13)
    line:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -10, yOff - 13)
    line:SetColorTexture(0.4, 0.3, 0.5, 0.5)
    return yOff - 18
end

local function OptButton(parent, text, yOff, onClick)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(232, OPT_BTN_HEIGHT)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, yOff)
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.15, 0.12, 0.22, 0.6)
    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(0.4, 0.2, 0.6, 0.3)
    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", 8, 0)
    label:SetText(text)
    btn:SetScript("OnClick", function()
        if onClick then onClick() end
    end)
    btn.label = label
    return btn, yOff - (OPT_BTN_HEIGHT + 3)
end

local function OptToggle(parent, text, yOff, getState, onToggle)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(232, OPT_BTN_HEIGHT)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, yOff)
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.12, 0.1, 0.18, 0.4)
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(0.3, 0.15, 0.4, 0.3)
    local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", 8, 0)
    label:SetText(text)
    local status = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    status:SetPoint("RIGHT", -8, 0)
    row.status = status
    local function UpdateStatus()
        if getState() then
            status:SetText("|cFF00FF00ON|r")
        else
            status:SetText("|cFFFF4444OFF|r")
        end
    end
    UpdateStatus()
    row:SetScript("OnClick", function()
        onToggle()
        UpdateStatus()
    end)
    row.UpdateStatus = UpdateStatus
    return row, yOff - (OPT_BTN_HEIGHT + 3)
end

-- Panels section
local y = OPT_Y
y = OptHeader(optPanel, "Panels", y)
OptButton(optPanel, "Toggle BiS Panel", y, function() optPanel:Hide() TogglePanel() end)
_, y = nil, y - (OPT_BTN_HEIGHT + 3)
OptButton(optPanel, "Toggle Loot Tracker", y, function() optPanel:Hide() SlashCmdList["ADHDBIS"]("loot") end)
_, y = nil, y - (OPT_BTN_HEIGHT + 3)
OptButton(optPanel, "|cFF00FF00LootRadar|r (M+ Upgrade Scanner)", y, function() optPanel:Hide() SlashCmdList["ADHDBIS"]("radar") end)
_, y = nil, y - (OPT_BTN_HEIGHT + 3)

-- Loot Tracker section
y = y - 4
y = OptHeader(optPanel, "Loot Tracker", y)
OptButton(optPanel, "New Loot Session", y, function() SlashCmdList["ADHDBIS"]("loot new") end)
_, y = nil, y - (OPT_BTN_HEIGHT + 3)
OptButton(optPanel, "Start Tracking", y, function() SlashCmdList["ADHDBIS"]("loot start") end)
_, y = nil, y - (OPT_BTN_HEIGHT + 3)
OptButton(optPanel, "Stop Tracking", y, function() SlashCmdList["ADHDBIS"]("loot stop") end)
_, y = nil, y - (OPT_BTN_HEIGHT + 3)
OptButton(optPanel, "Loot Summary (to chat)", y, function() SlashCmdList["ADHDBIS"]("loot summary") end)
_, y = nil, y - (OPT_BTN_HEIGHT + 3)
OptButton(optPanel, "Show Wishlist", y, function() SlashCmdList["ADHDBIS"]("loot wishlist") end)
_, y = nil, y - (OPT_BTN_HEIGHT + 3)
OptButton(optPanel, "Change Alert Sound", y, function() SlashCmdList["ADHDBIS"]("loot sound") end)
_, y = nil, y - (OPT_BTN_HEIGHT + 3)

-- LootRadar section
y = y - 4
y = OptHeader(optPanel, "LootRadar", y)
OptButton(optPanel, "Toggle Whisper/Party Mode", y, function() SlashCmdList["ADHDBIS"]("radar mode") end)
_, y = nil, y - (OPT_BTN_HEIGHT + 3)
OptButton(optPanel, "Clear Results", y, function() SlashCmdList["ADHDBIS"]("radar clear") end)
_, y = nil, y - (OPT_BTN_HEIGHT + 3)

-- Toggles section
y = y - 4
y = OptHeader(optPanel, "Debug / Advanced", y)
OptToggle(optPanel, "Loot Debug Logging", y,
    function() return ADHDBiS_LootDB and ADHDBiS_LootDB.debugMode end,
    function() SlashCmdList["ADHDBIS"]("loot debug toggle") end)
_, y = nil, y - (OPT_BTN_HEIGHT + 3)
OptButton(optPanel, "Show Debug Log", y, function() SlashCmdList["ADHDBIS"]("loot debug") end)
_, y = nil, y - (OPT_BTN_HEIGHT + 3)
OptButton(optPanel, "Copy Debug Log", y, function() optPanel:Hide() SlashCmdList["ADHDBIS"]("loot debug copy") end)
_, y = nil, y - (OPT_BTN_HEIGHT + 3)
OptButton(optPanel, "Clear Debug Log", y, function() SlashCmdList["ADHDBIS"]("loot debug clear") end)
_, y = nil, y - (OPT_BTN_HEIGHT + 3)

-- Minimap section
y = y - 4
y = OptHeader(optPanel, "Minimap", y)
OptButton(optPanel, "Hide Minimap Button", y, function() SlashCmdList["ADHDBIS"]("minimap hide") optPanel:Hide() end)
_, y = nil, y - (OPT_BTN_HEIGHT + 3)
OptButton(optPanel, "Reset Minimap Position", y, function() SlashCmdList["ADHDBIS"]("minimap reset") end)
_, y = nil, y - (OPT_BTN_HEIGHT + 3)

-- Version info at bottom
local verLabel = optPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
verLabel:SetPoint("BOTTOMLEFT", optPanel, "BOTTOMLEFT", 10, 8)
verLabel:SetTextColor(0.4, 0.4, 0.4)
verLabel:SetText("v" .. (C_AddOns.GetAddOnMetadata("ADHDBiS", "Version") or "?"))

-- Resize panel to fit content
optPanel:SetHeight(math.abs(y) + 30)

minimapBtn:SetScript("OnClick", function(self, button)
    if button == "LeftButton" then
        TogglePanel()
    elseif button == "RightButton" then
        if optPanel:IsShown() then
            optPanel:Hide()
        else
            optPanel:ClearAllPoints()
            optPanel:SetPoint("TOPRIGHT", self, "BOTTOMLEFT", 0, 0)
            optPanel:Show()
        end
    elseif button == "MiddleButton" then
        if ns.ToggleLootRadar then
            ns.ToggleLootRadar("")
        end
    end
end)

-- Load saved position on PLAYER_ENTERING_WORLD (deferred)
local mmInitFrame = CreateFrame("Frame")
mmInitFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
mmInitFrame:SetScript("OnEvent", function(self)
    local db = GetDB()
    RestoreMinimapPosition()
    -- Hide if user previously chose to hide
    if db.minimapHidden then
        minimapBtn:Hide()
    end
    self:UnregisterAllEvents()
end)

-- ============================================================
-- TOOLTIP BiS INTEGRATION (performance-critical: cached lookups only)
-- ============================================================

local tooltipHooked = false
local function HookTooltip()
    if tooltipHooked then return end
    tooltipHooked = true

    -- Hook into TooltipDataProcessor for item tooltips (modern API, Midnight+)
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
            if tooltip ~= GameTooltip then return end
            if not data or not data.id then return end

            local itemID = data.id
            local entries = bisLookup[itemID]
            if not entries then return end

            -- Deduplicate: show each class/spec combo once
            local seen = {}
            for _, entry in ipairs(entries) do
                local key = entry.class .. entry.spec .. entry.gearSource
                if not seen[key] then
                    seen[key] = true
                    local gsLabel = entry.gearSource == "mythicplus" and "M+" or "Raid"
                    tooltip:AddLine("|cFF9482C9BiS:|r " .. entry.spec .. " " .. entry.class .. " |cFF888888(" .. gsLabel .. ")|r", 1, 1, 1)
                end
            end
            tooltip:Show()
        end)
    end
end

-- Hook tooltip after BiS lookup is built (deferred to avoid load-time overhead)
local tooltipInitFrame = CreateFrame("Frame")
tooltipInitFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
tooltipInitFrame:SetScript("OnEvent", function(self)
    C_Timer.After(1, function()
        BuildBiSLookup()
        HookTooltip()
    end)
    self:UnregisterAllEvents()
end)

-- ============================================================
-- SLASH COMMAND
-- ============================================================

SLASH_ADHDBIS1 = "/adhd"
SlashCmdList["ADHDBIS"] = function(msg)
    local cmd = msg:lower():trim()
    if cmd == "bis" then
        TogglePanel()
    elseif cmd == "dismiss" then
        local db = GetDB()
        db.hideSupportMsg = true
        print("|cFF9482C9ADHDBiS:|r Support message hidden. Thank you for using the addon!")
    elseif cmd == "minimap hide" then
        local db = GetDB()
        db.minimapHidden = true
        minimapBtn:Hide()
        print("|cFF9482C9ADHDBiS:|r Minimap button hidden. Type |cFFFFFFFF/adhd minimap show|r to restore.")
    elseif cmd == "minimap show" then
        local db = GetDB()
        db.minimapHidden = false
        minimapBtn:Show()
        RestoreMinimapPosition()
        print("|cFF9482C9ADHDBiS:|r Minimap button visible.")
    elseif cmd == "minimap reset" then
        local db = GetDB()
        db.minimapX = nil
        db.minimapY = nil
        db.minimapHidden = false
        minimapBtn:Show()
        RestoreMinimapPosition()
        print("|cFF9482C9ADHDBiS:|r Minimap button reset to default position.")
    elseif cmd == "version" then
        local tocVersion = C_AddOns.GetAddOnMetadata("ADHDBiS", "Version") or "?"
        print("|cFF9482C9ADHDBiS:|r v" .. tocVersion)
    elseif cmd == "loot" or cmd:find("^loot") then
        -- Delegate to loot tracker
        local subCmd = cmd:match("^loot%s+(.+)") or ""
        if ns.ToggleLootTracker then
            ns.ToggleLootTracker(subCmd)
        else
            print("|cFF9482C9ADHDBiS:|r Loot Tracker not loaded.")
        end
    elseif cmd == "radar" or cmd:find("^radar") then
        -- Delegate to loot radar
        local subCmd = cmd:match("^radar%s+(.+)") or ""
        if ns.ToggleLootRadar then
            ns.ToggleLootRadar(subCmd)
        else
            print("|cFF9482C9ADHDBiS:|r LootRadar not loaded.")
        end
    else
        print("|cFF9482C9ADHDBiS:|r Commands:")
        print("  |cFFFFFFFF/adhd bis|r - Toggle BiS panel")
        print("  |cFFFFFFFF/adhd loot|r - Toggle Loot Tracker")
        print("  |cFFFFFFFF/adhd loot help|r - All loot tracker commands")
        print("  |cFFFFFFFF/adhd radar|r - Toggle LootRadar (M+ upgrade scanner)")
        print("  |cFFFFFFFF/adhd radar help|r - LootRadar commands")
        print("  |cFFFFFFFF/adhd minimap hide|r - Hide minimap button")
        print("  |cFFFFFFFF/adhd minimap show|r - Show minimap button")
        print("  |cFFFFFFFF/adhd minimap reset|r - Reset button to default position")
        print("  |cFFFFFFFF/adhd version|r - Show addon version")
    end
end

print("|cFF9482C9ADHDBiS|r loaded. Type |cFFFFFFFF/adhd bis|r to open.")
