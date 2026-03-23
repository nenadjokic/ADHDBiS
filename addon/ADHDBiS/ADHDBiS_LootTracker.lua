-- ADHDBiS Loot Tracker: Track raid loot drops in a grid display
-- =============================================================================

local addonName, ns = ...

-- SavedVariables for loot history (initialized in event handler)
ADHDBiS_LootDB = ADHDBiS_LootDB or {}

local MAX_SESSIONS = 5

-- ============================================================
-- CONSTANTS
-- ============================================================

local GRID_ICON_SIZE = 40
local GRID_CELL_WIDTH = 58
local GRID_CELL_HEIGHT = 84 -- icon + ilvl + track + player
local GRID_PADDING = 4
local GRID_BORDER_SIZE = 2

-- Item quality colors for borders
local QUALITY_COLORS = {
    [0] = {0.62, 0.62, 0.62}, -- Poor (gray)
    [1] = {1.00, 1.00, 1.00}, -- Common (white)
    [2] = {0.12, 1.00, 0.00}, -- Uncommon (green)
    [3] = {0.00, 0.44, 0.87}, -- Rare (blue)
    [4] = {0.64, 0.21, 0.93}, -- Epic (purple)
    [5] = {1.00, 0.50, 0.00}, -- Legendary (orange)
    [6] = {0.90, 0.80, 0.50}, -- Artifact
    [7] = {0.00, 0.80, 1.00}, -- Heirloom
}

-- ============================================================
-- STATE
-- ============================================================

local currentSession = nil  -- pointer to active session in ADHDBiS_LootDB.sessions
local currentEncounter = nil -- {name, id} of current boss fight
local selectedSessionIndex = 1
local lootGridCells = {}
local lootSectionHeaders = {}
local isTracking = false
local pendingInstanceEntry = nil -- set during popup to defer session creation

-- ============================================================
-- LOOT TRACKER FRAME
-- ============================================================

local lootFrame = CreateFrame("Frame", "ADHDBiSLootFrame", UIParent, "BackdropTemplate")
lootFrame:SetSize(420, 400)
lootFrame:SetPoint("CENTER", UIParent, "CENTER", 250, 0)
lootFrame:SetFrameStrata("HIGH")
lootFrame:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
})
lootFrame:SetBackdropColor(0.05, 0.05, 0.08, 0.92)
lootFrame:SetBackdropBorderColor(0.6, 0.3, 0.2, 0.9)
lootFrame:SetClampedToScreen(true)
lootFrame:EnableMouse(true)
lootFrame:SetMovable(true)
lootFrame:SetResizable(true)
lootFrame:SetResizeBounds(300, 250, 800, 900)
lootFrame:RegisterForDrag("LeftButton")
lootFrame:Hide()

lootFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
lootFrame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local db = ADHDBiS_LootDB
    local point, _, relPoint, x, y = self:GetPoint()
    db.lootWindowPoint = { point, nil, relPoint, x, y }
end)

-- Resize handle
local lootResize = CreateFrame("Button", nil, lootFrame)
lootResize:SetSize(16, 16)
lootResize:SetPoint("BOTTOMRIGHT", lootFrame, "BOTTOMRIGHT", -2, 2)
lootResize:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
lootResize:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
lootResize:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")

lootResize:SetScript("OnMouseDown", function() lootFrame:StartSizing("BOTTOMRIGHT") end)
lootResize:SetScript("OnMouseUp", function()
    lootFrame:StopMovingOrSizing()
    ADHDBiS_LootDB.lootWindowWidth = lootFrame:GetWidth()
    ADHDBiS_LootDB.lootWindowHeight = lootFrame:GetHeight()
    RefreshLootGrid()
end)

-- ============================================================
-- TITLE BAR
-- ============================================================

local lootTitleBar = CreateFrame("Frame", nil, lootFrame)
lootTitleBar:SetHeight(24)
lootTitleBar:SetPoint("TOPLEFT", lootFrame, "TOPLEFT", 6, -6)
lootTitleBar:SetPoint("TOPRIGHT", lootFrame, "TOPRIGHT", -6, -6)

local lootTitle = lootTitleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
lootTitle:SetPoint("LEFT", lootTitleBar, "LEFT", 2, 0)
lootTitle:SetText("|cFF9482C9ADHDBiS|r |cFFFFD100Loot Tracker|r")

-- Close button
local lootCloseBtn = CreateFrame("Button", nil, lootTitleBar)
lootCloseBtn:SetSize(22, 22)
lootCloseBtn:SetPoint("RIGHT", lootTitleBar, "RIGHT", 4, 0)
local lootCloseTxt = lootCloseBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
lootCloseTxt:SetPoint("CENTER")
lootCloseTxt:SetText("|cFFFF4444X|r")
lootCloseBtn:SetScript("OnClick", function() lootFrame:Hide() end)
lootCloseBtn:SetScript("OnEnter", function() lootCloseTxt:SetText("|cFFFF8888X|r") end)
lootCloseBtn:SetScript("OnLeave", function() lootCloseTxt:SetText("|cFFFF4444X|r") end)

-- Filter dropdown button
local filterBtn = CreateFrame("Button", nil, lootTitleBar)
filterBtn:SetSize(50, 18)
filterBtn:SetPoint("RIGHT", lootCloseBtn, "LEFT", -4, 0)
local filterBg = filterBtn:CreateTexture(nil, "BACKGROUND")
filterBg:SetAllPoints()
filterBg:SetColorTexture(0.2, 0.2, 0.3, 0.7)
local filterTxt = filterBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
filterTxt:SetPoint("CENTER")
filterTxt:SetText("|cFFAAAAAAFilter|r")

-- Filter dropdown panel
local filterDropdown = CreateFrame("Frame", "ADHDBiSLootFilterDropdown", lootFrame, "BackdropTemplate")
filterDropdown:SetSize(140, 142)
filterDropdown:SetPoint("TOPRIGHT", filterBtn, "BOTTOMRIGHT", 0, -2)
filterDropdown:SetFrameStrata("DIALOG")
filterDropdown:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
})
filterDropdown:SetBackdropColor(0.08, 0.08, 0.12, 0.95)
filterDropdown:SetBackdropBorderColor(0.5, 0.3, 0.6, 0.8)
filterDropdown:Hide()
filterDropdown:EnableMouse(true)

-- Filter options definition: {key, label, color}
local FILTER_OPTIONS = {
    { key = "gear",       label = "Gear",        color = "|cFF00BBFF" },
    { key = "mount",      label = "Mounts",      color = "|cFFFF8800" },
    { key = "recipe",     label = "Recipes",      color = "|cFF00DD00" },
    { key = "consumable", label = "Consumables",  color = "|cFFBBBBBB" },
    { key = "other",      label = "Other",        color = "|cFF888888" },
    { key = "epicOnly",   label = "Epic+ Only",   color = "|cFFA335EE" },
}

local filterCheckboxes = {}

local function UpdateFilterButtonText()
    -- Count active category filters (excluding epicOnly)
    local activeCount = 0
    local totalCats = 5
    for _, opt in ipairs(FILTER_OPTIONS) do
        if opt.key ~= "epicOnly" and lootFilters[opt.key] then
            activeCount = activeCount + 1
        end
    end
    if activeCount == totalCats and not lootFilters.epicOnly then
        filterTxt:SetText("|cFFAAAAAAFilter|r")
        filterBg:SetColorTexture(0.2, 0.2, 0.3, 0.7)
    else
        filterTxt:SetText("|cFF9482C9Filter|r")
        filterBg:SetColorTexture(0.3, 0.15, 0.4, 0.7)
    end
end

for i, opt in ipairs(FILTER_OPTIONS) do
    local row = CreateFrame("Button", nil, filterDropdown)
    row:SetSize(134, 20)
    row:SetPoint("TOPLEFT", filterDropdown, "TOPLEFT", 3, -3 - (i - 1) * 22)

    local rowBg = row:CreateTexture(nil, "BACKGROUND")
    rowBg:SetAllPoints()
    rowBg:SetColorTexture(0, 0, 0, 0)
    row.bg = rowBg

    local check = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    check:SetPoint("LEFT", row, "LEFT", 4, 0)
    check:SetWidth(16)
    row.check = check

    local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", check, "RIGHT", 2, 0)
    label:SetText(opt.color .. opt.label .. "|r")

    -- Add separator line before Epic+ Only
    if opt.key == "epicOnly" then
        local sep = filterDropdown:CreateTexture(nil, "ARTWORK")
        sep:SetHeight(1)
        sep:SetPoint("TOPLEFT", filterDropdown, "TOPLEFT", 6, -3 - (i - 1) * 22 + 3)
        sep:SetPoint("TOPRIGHT", filterDropdown, "TOPRIGHT", -6, -3 - (i - 1) * 22 + 3)
        sep:SetColorTexture(0.4, 0.3, 0.5, 0.5)
    end

    local function UpdateCheck()
        if lootFilters[opt.key] then
            check:SetText("|cFF00FF00+|r")
        else
            check:SetText("|cFF666666-|r")
        end
    end
    UpdateCheck()

    row:SetScript("OnClick", function()
        lootFilters[opt.key] = not lootFilters[opt.key]
        UpdateCheck()
        UpdateFilterButtonText()
        SaveFilters()
        RefreshLootGrid()
    end)

    row:SetScript("OnEnter", function() rowBg:SetColorTexture(0.3, 0.2, 0.4, 0.4) end)
    row:SetScript("OnLeave", function() rowBg:SetColorTexture(0, 0, 0, 0) end)

    filterCheckboxes[opt.key] = { row = row, updateCheck = UpdateCheck }
end

filterBtn:SetScript("OnClick", function()
    if filterDropdown:IsShown() then
        filterDropdown:Hide()
    else
        -- Update checkmarks to current state
        for _, opt in ipairs(FILTER_OPTIONS) do
            if filterCheckboxes[opt.key] then
                filterCheckboxes[opt.key].updateCheck()
            end
        end
        filterDropdown:Show()
    end
end)

-- Close dropdown when clicking elsewhere
filterDropdown:SetScript("OnShow", function(self)
    self:SetScript("OnUpdate", function(self2)
        if not MouseIsOver(self2) and not MouseIsOver(filterBtn) and IsMouseButtonDown("LeftButton") then
            self2:Hide()
        end
    end)
end)
filterDropdown:SetScript("OnHide", function(self)
    self:SetScript("OnUpdate", nil)
end)

-- Clear button
local clearBtn = CreateFrame("Button", nil, lootTitleBar)
clearBtn:SetSize(45, 18)
clearBtn:SetPoint("RIGHT", filterBtn, "LEFT", -4, 0)
local clearBg = clearBtn:CreateTexture(nil, "BACKGROUND")
clearBg:SetAllPoints()
clearBg:SetColorTexture(0.5, 0.2, 0.2, 0.7)
local clearTxt = clearBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
clearTxt:SetPoint("CENTER")
clearTxt:SetText("Clear")
clearBtn:SetScript("OnClick", function()
    -- Wipe ALL sessions and reset state completely
    ADHDBiS_LootDB.sessions = {}
    currentSession = nil
    selectedSessionIndex = 1
    isTracking = false
    currentEncounter = nil
    lastEncounterName = nil
    lastEncounterTime = 0
    UpdateSessionLabel()
    UpdateStatus()
    RefreshLootGrid()
    print("|cFF9482C9ADHDBiS:|r All loot sessions cleared. New session starts on next instance entry.")
end)

-- ============================================================
-- SESSION SELECTOR
-- ============================================================

local sessionBar = CreateFrame("Frame", nil, lootFrame)
sessionBar:SetHeight(22)
sessionBar:SetPoint("TOPLEFT", lootTitleBar, "BOTTOMLEFT", 0, -2)
sessionBar:SetPoint("RIGHT", lootFrame, "RIGHT", -8, 0)

local sessionLabel = sessionBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
sessionLabel:SetPoint("LEFT", sessionBar, "LEFT", 0, 0)
sessionLabel:SetText("|cFFAAAAAASession:|r")

-- Session dropdown button
local sessionBtn = CreateFrame("Frame", nil, sessionBar)
sessionBtn:SetSize(200, 20)
sessionBtn:SetPoint("LEFT", sessionLabel, "RIGHT", 4, 0)

local sessionBg = sessionBtn:CreateTexture(nil, "BACKGROUND")
sessionBg:SetAllPoints()
sessionBg:SetColorTexture(0.12, 0.12, 0.18, 0.9)

local sessionBorder = sessionBtn:CreateTexture(nil, "BORDER")
sessionBorder:SetPoint("TOPLEFT", sessionBtn, "TOPLEFT", -1, 1)
sessionBorder:SetPoint("BOTTOMRIGHT", sessionBtn, "BOTTOMRIGHT", 1, -1)
sessionBorder:SetColorTexture(0.3, 0.2, 0.5, 0.6)

local sessionBtnLabel = sessionBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
sessionBtnLabel:SetPoint("LEFT", sessionBtn, "LEFT", 6, 0)
sessionBtnLabel:SetPoint("RIGHT", sessionBtn, "RIGHT", -14, 0)
sessionBtnLabel:SetJustifyH("LEFT")
sessionBtnLabel:SetWordWrap(false)
sessionBtnLabel:SetText("No sessions")

local sessionArrow = sessionBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
sessionArrow:SetPoint("RIGHT", sessionBtn, "RIGHT", -4, 0)
sessionArrow:SetText("|cFF888888v|r")

-- Session dropdown menu
local sessionDropFrame = CreateFrame("Frame", "ADHDBiSSessionDrop", UIParent, "BackdropTemplate")
sessionDropFrame:SetFrameStrata("FULLSCREEN_DIALOG")
sessionDropFrame:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
})
sessionDropFrame:SetBackdropColor(0.08, 0.08, 0.12, 0.95)
sessionDropFrame:SetBackdropBorderColor(0.4, 0.2, 0.6, 0.9)
sessionDropFrame:EnableMouse(true)
sessionDropFrame:Hide()
sessionDropFrame.buttons = {}

sessionDropFrame:SetScript("OnShow", function(self)
    self:RegisterEvent("GLOBAL_MOUSE_DOWN")
end)
sessionDropFrame:SetScript("OnHide", function(self)
    self:UnregisterEvent("GLOBAL_MOUSE_DOWN")
end)
sessionDropFrame:SetScript("OnEvent", function(self, event)
    if event == "GLOBAL_MOUSE_DOWN" and not self:IsMouseOver() then
        self:Hide()
    end
end)

sessionBtn:EnableMouse(true)
sessionBtn:SetScript("OnMouseDown", function(self)
    local sessions = ADHDBiS_LootDB.sessions or {}
    if #sessions == 0 then return end

    for _, btn in ipairs(sessionDropFrame.buttons) do btn:Hide() end

    local ITEM_HEIGHT = 20
    for i, session in ipairs(sessions) do
        local btn = sessionDropFrame.buttons[i]
        if not btn then
            btn = CreateFrame("Button", nil, sessionDropFrame)
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
            sessionDropFrame.buttons[i] = btn
        end

        local label = session.name or ("Session " .. i)
        local itemCount = #(session.items or {})
        label = label .. " (" .. itemCount .. " items)"

        btn:SetPoint("TOPLEFT", sessionDropFrame, "TOPLEFT", 4, -(4 + (i - 1) * ITEM_HEIGHT))
        btn:SetPoint("RIGHT", sessionDropFrame, "RIGHT", -4, 0)
        btn.text:SetText(label)
        btn.check:SetText(i == selectedSessionIndex and "|cFF00FF00>|r" or "")
        btn:SetScript("OnClick", function()
            sessionDropFrame:Hide()
            selectedSessionIndex = i
            currentSession = sessions[i]
            UpdateSessionLabel()
            RefreshLootGrid()
        end)
        btn:Show()
    end

    sessionDropFrame:SetSize(self:GetWidth() + 8, #sessions * ITEM_HEIGHT + 8)
    sessionDropFrame:ClearAllPoints()
    sessionDropFrame:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -2)
    sessionDropFrame:Show()
end)

-- ============================================================
-- TRACKING STATUS
-- ============================================================

local statusText = lootFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
statusText:SetPoint("BOTTOMLEFT", lootFrame, "BOTTOMLEFT", 8, 6)
statusText:SetPoint("BOTTOMRIGHT", lootFrame, "BOTTOMRIGHT", -20, 6)
statusText:SetJustifyH("LEFT")
statusText:SetTextColor(0.5, 0.5, 0.5, 1)

-- ============================================================
-- SCROLL FRAME
-- ============================================================

local lootScrollFrame = CreateFrame("ScrollFrame", "ADHDBiSLootScroll", lootFrame, "UIPanelScrollFrameTemplate")
lootScrollFrame:SetPoint("TOPLEFT", sessionBar, "BOTTOMLEFT", 0, -4)
lootScrollFrame:SetPoint("BOTTOMRIGHT", lootFrame, "BOTTOMRIGHT", -28, 24)

local lootScrollChild = CreateFrame("Frame", nil, lootScrollFrame)
lootScrollChild:SetHeight(1)
lootScrollFrame:SetScrollChild(lootScrollChild)

-- ============================================================
-- GRID CELL POOL (Loot Tracker)
-- ============================================================

-- Upgrade detection: compare item ilvl with equipped ilvl in same slot
local EQUIP_LOC_TO_SLOT = {
    INVTYPE_HEAD = 1, INVTYPE_NECK = 2, INVTYPE_SHOULDER = 3,
    INVTYPE_CHEST = 5, INVTYPE_ROBE = 5, INVTYPE_WAIST = 6,
    INVTYPE_LEGS = 7, INVTYPE_FEET = 8, INVTYPE_WRIST = 9,
    INVTYPE_HAND = 10, INVTYPE_FINGER = 11, INVTYPE_TRINKET = 13,
    INVTYPE_CLOAK = 15, INVTYPE_WEAPON = 16, INVTYPE_2HWEAPON = 16,
    INVTYPE_WEAPONMAINHAND = 16, INVTYPE_WEAPONOFFHAND = 17,
    INVTYPE_HOLDABLE = 17, INVTYPE_SHIELD = 17, INVTYPE_RANGED = 16,
}

local function IsUpgradeForPlayer(itemID, itemIlvl)
    if not itemID or not itemIlvl or itemIlvl == 0 then return false end
    local _, _, _, equipLoc = GetItemInfoInstant(itemID)
    if not equipLoc or equipLoc == "" then return false end
    local slotID = EQUIP_LOC_TO_SLOT[equipLoc]
    if not slotID then return false end
    -- Check both ring/trinket slots
    local slotsToCheck = {slotID}
    if equipLoc == "INVTYPE_FINGER" then slotsToCheck = {11, 12} end
    if equipLoc == "INVTYPE_TRINKET" then slotsToCheck = {13, 14} end
    local lowestEquipped = 99999
    for _, sid in ipairs(slotsToCheck) do
        local equippedLink = GetInventoryItemLink("player", sid)
        if equippedLink then
            local eIlvl = GetDetailedItemLevelInfo(equippedLink)
            if eIlvl and eIlvl < lowestEquipped then
                lowestEquipped = eIlvl
            end
        else
            lowestEquipped = 0 -- empty slot = definite upgrade
        end
    end
    return itemIlvl > lowestEquipped
end

-- Wishlist helpers
local function IsWishlisted(itemID)
    return ADHDBiS_LootDB.wishlist and ADHDBiS_LootDB.wishlist[itemID]
end

local function ToggleWishlist(itemID)
    if not ADHDBiS_LootDB.wishlist then ADHDBiS_LootDB.wishlist = {} end
    if ADHDBiS_LootDB.wishlist[itemID] then
        ADHDBiS_LootDB.wishlist[itemID] = nil
    else
        ADHDBiS_LootDB.wishlist[itemID] = true
    end
end

-- Filter state (initialized from DB in InitDB, defaults here)
local FILTER_DEFAULTS = {
    gear = true,
    mount = true,
    recipe = true,
    consumable = false,
    other = false,
    epicOnly = false,
}
local lootFilters = {}
for k, v in pairs(FILTER_DEFAULTS) do lootFilters[k] = v end

local function GetLootGridCell(index)
    if lootGridCells[index] then
        lootGridCells[index]:Show()
        return lootGridCells[index]
    end

    local cell = CreateFrame("Button", nil, lootScrollChild)
    cell:SetSize(GRID_CELL_WIDTH, GRID_CELL_HEIGHT)
    cell:EnableMouse(true)

    -- Quality border (behind icon)
    local borderTex = cell:CreateTexture(nil, "BACKGROUND")
    borderTex:SetSize(GRID_ICON_SIZE + GRID_BORDER_SIZE * 2, GRID_ICON_SIZE + GRID_BORDER_SIZE * 2)
    borderTex:SetPoint("TOP", cell, "TOP", 0, 0)
    borderTex:SetColorTexture(0.64, 0.21, 0.93, 1)
    cell.borderTex = borderTex

    -- Icon
    local icon = cell:CreateTexture(nil, "ARTWORK")
    icon:SetSize(GRID_ICON_SIZE, GRID_ICON_SIZE)
    icon:SetPoint("CENTER", borderTex, "CENTER", 0, 0)
    cell.icon = icon

    -- Upgrade arrow overlay (top-left of icon)
    local upgradeArrow = cell:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    upgradeArrow:SetPoint("TOPLEFT", borderTex, "TOPLEFT", 1, -1)
    upgradeArrow:SetText("")
    cell.upgradeArrow = upgradeArrow

    -- Wishlist star overlay (top-right of icon)
    local wishlistStar = cell:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    wishlistStar:SetPoint("TOPRIGHT", borderTex, "TOPRIGHT", -1, -1)
    wishlistStar:SetText("")
    cell.wishlistStar = wishlistStar

    -- Line 1: ilvl
    local ilvlLabel = cell:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ilvlLabel:SetPoint("TOP", borderTex, "BOTTOM", 0, -1)
    ilvlLabel:SetWidth(GRID_CELL_WIDTH)
    ilvlLabel:SetJustifyH("CENTER")
    ilvlLabel:SetWordWrap(false)
    cell.ilvlLabel = ilvlLabel

    -- Line 2: track
    local trackLabel = cell:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    trackLabel:SetPoint("TOP", ilvlLabel, "BOTTOM", 0, 0)
    trackLabel:SetWidth(GRID_CELL_WIDTH)
    trackLabel:SetJustifyH("CENTER")
    trackLabel:SetWordWrap(false)
    trackLabel:SetTextColor(0.7, 0.7, 0.7, 1)
    cell.trackLabel = trackLabel

    -- Line 3: player name
    local playerLabel = cell:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    playerLabel:SetPoint("TOP", trackLabel, "BOTTOM", 0, 0)
    playerLabel:SetWidth(GRID_CELL_WIDTH)
    playerLabel:SetJustifyH("CENTER")
    playerLabel:SetWordWrap(false)
    cell.playerLabel = playerLabel

    -- Highlight
    local highlight = cell:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints(borderTex)
    highlight:SetColorTexture(1, 1, 1, 0.2)

    -- Tooltip
    cell:SetScript("OnEnter", function(self)
        local ref = self.storedLink and self.storedLink:match("|H(item:[^|]+)|h") or (self.itemID and ("item:" .. self.itemID))
        if not ref then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(ref)
        if self.isUpgrade then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("|cFF00FF00UPGRADE for you!|r", 0, 1, 0)
        end
        if self.isWishlisted then
            GameTooltip:AddLine("|cFFFFD100Wishlisted|r", 1, 0.82, 0)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cFF888888Shift+Click: Preview | Ctrl+Click: Chat | Right+Click: Wishlist|r", 0.5, 0.5, 0.5, true)
        GameTooltip:Show()
    end)
    cell:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Click handlers
    cell:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    cell:SetScript("OnClick", function(self, button)
        if not self.itemID and not self.storedLink then return end

        local link = self.storedLink
        if not link and self.itemID then
            _, link = C_Item.GetItemInfo(self.itemID)
        end

        if button == "LeftButton" and IsShiftKeyDown() then
            if link then DressUpLink(link) end
        elseif button == "LeftButton" and IsControlKeyDown() then
            if link then ChatEdit_InsertLink(link) end
        elseif button == "RightButton" then
            -- Right-click: toggle wishlist
            if self.itemID then
                ToggleWishlist(self.itemID)
                local wishlisted = IsWishlisted(self.itemID)
                self.wishlistStar:SetText(wishlisted and "|cFFFFD100*|r" or "")
                self.isWishlisted = wishlisted
                local name = C_Item.GetItemNameByID(self.itemID) or "Item"
                if wishlisted then
                    print("|cFF9482C9ADHDBiS:|r |cFFFFD100*|r " .. (link or name) .. " added to wishlist.")
                else
                    print("|cFF9482C9ADHDBiS:|r " .. (link or name) .. " removed from wishlist.")
                end
            end
        end
    end)

    lootGridCells[index] = cell
    return cell
end

local function HideAllLootGridCells()
    for _, cell in ipairs(lootGridCells) do
        cell:Hide()
        cell.itemID = nil
        cell.storedLink = nil
        cell.isUpgrade = nil
        cell.isWishlisted = nil
    end
end

local function GetLootSectionHeader(index)
    if lootSectionHeaders[index] then
        lootSectionHeaders[index]:Show()
        return lootSectionHeaders[index]
    end

    local hdr = CreateFrame("Frame", nil, lootScrollChild)
    hdr:SetHeight(20)

    local bg = hdr:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.15, 0.1, 0.2, 0.6)
    hdr.bg = bg

    local text = hdr:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("LEFT", hdr, "LEFT", 4, 0)
    text:SetPoint("RIGHT", hdr, "RIGHT", -4, 0)
    text:SetJustifyH("LEFT")
    hdr.text = text

    lootSectionHeaders[index] = hdr
    return hdr
end

local function HideAllLootHeaders()
    for _, hdr in ipairs(lootSectionHeaders) do hdr:Hide() end
end

-- ============================================================
-- ITEM HELPERS
-- ============================================================

-- Item category classification using WoW classID/subclassID
-- classID: 0=Consumable, 2=Weapon, 3=Gem, 4=Armor, 5=Reagent,
--          7=Tradeskill, 8=ItemEnhancement, 9=Recipe, 15=Miscellaneous
local function GetItemCategory(itemID)
    if not itemID then return "other" end
    local _, _, _, _, _, classID, subclassID = GetItemInfoInstant(itemID)
    if not classID then return "other" end
    -- Gear: weapons and equippable armor
    if classID == 2 then return "gear" end -- Weapon
    if classID == 4 then -- Armor
        local _, _, _, equipLoc = GetItemInfoInstant(itemID)
        if equipLoc and equipLoc ~= "" and equipLoc ~= "INVTYPE_NON_EQUIP" then
            return "gear"
        end
        return "other"
    end
    -- Mount: Miscellaneous, subclass 5
    if classID == 15 and subclassID == 5 then return "mount" end
    -- Recipe
    if classID == 9 then return "recipe" end
    -- Consumable / reagent / tradeskill / enhancement
    if classID == 0 or classID == 5 or classID == 7 or classID == 8 then return "consumable" end
    -- Gem
    if classID == 3 then return "gear" end
    return "other"
end

local function GetItemIcon(itemID)
    if not itemID then return "Interface\\Icons\\INV_Misc_QuestionMark" end
    local _, _, _, _, icon = GetItemInfoInstant(itemID)
    return icon or "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- Get quality from item link (actual drop quality, not base)
local function GetItemQualityFromLink(itemLink)
    if itemLink then
        local _, _, quality = GetItemInfo(itemLink)
        if quality then return quality end
    end
    return 3
end

-- Get actual item level from link (respects difficulty scaling, upgrades, etc.)
local function GetItemLevelFromLink(itemLink)
    if itemLink then
        local ilvl = GetDetailedItemLevelInfo(itemLink)
        if ilvl then return ilvl end
    end
    return 0
end

-- Determine gear track from item level
-- Midnight Season 1 approximate ranges (may need updating per season):
local function GetGearTrack(ilvl)
    if not ilvl or ilvl == 0 then return "", "" end
    -- Midnight Season 1 tracks (approximate):
    -- Explorer:    558-577  (1/8 to 8/8)
    -- Adventurer:  571-590  (1/8 to 8/8)
    -- Veteran:     584-603  (1/8 to 8/8)
    -- Champion:    597-616  (1/8 to 8/8)
    -- Hero:        610-626  (1/6 to 6/6)
    -- Myth:        623-639  (1/6 to 6/6)
    if ilvl >= 623 then
        local step = math.floor((ilvl - 623) / 3) + 1
        if step > 6 then step = 6 end
        return "Myth", step .. "/6"
    elseif ilvl >= 610 then
        local step = math.floor((ilvl - 610) / 3) + 1
        if step > 6 then step = 6 end
        return "Hero", step .. "/6"
    elseif ilvl >= 597 then
        local step = math.floor((ilvl - 597) / 3) + 1
        if step > 8 then step = 8 end
        return "Champ", step .. "/8"
    elseif ilvl >= 584 then
        local step = math.floor((ilvl - 584) / 3) + 1
        if step > 8 then step = 8 end
        return "Vet", step .. "/8"
    elseif ilvl >= 571 then
        local step = math.floor((ilvl - 571) / 3) + 1
        if step > 8 then step = 8 end
        return "Adv", step .. "/8"
    elseif ilvl >= 558 then
        local step = math.floor((ilvl - 558) / 3) + 1
        if step > 8 then step = 8 end
        return "Expl", step .. "/8"
    end
    return "", ""
end

local function GetItemEquipSlot(itemID)
    if not itemID then return "" end
    local _, _, _, equipLoc = GetItemInfoInstant(itemID)
    if not equipLoc or equipLoc == "" then return "" end
    local slotNames = {
        INVTYPE_HEAD = "Head", INVTYPE_NECK = "Neck", INVTYPE_SHOULDER = "Shld",
        INVTYPE_BODY = "Shirt", INVTYPE_CHEST = "Chest", INVTYPE_ROBE = "Chest",
        INVTYPE_WAIST = "Waist", INVTYPE_LEGS = "Legs", INVTYPE_FEET = "Feet",
        INVTYPE_WRIST = "Wrist", INVTYPE_HAND = "Hands", INVTYPE_FINGER = "Ring",
        INVTYPE_TRINKET = "Trk", INVTYPE_CLOAK = "Back", INVTYPE_WEAPON = "Wep",
        INVTYPE_SHIELD = "Shield", INVTYPE_2HWEAPON = "2H", INVTYPE_WEAPONMAINHAND = "MH",
        INVTYPE_WEAPONOFFHAND = "OH", INVTYPE_HOLDABLE = "OH", INVTYPE_RANGED = "Ranged",
    }
    return slotNames[equipLoc] or ""
end

-- ============================================================
-- SESSION MANAGEMENT
-- ============================================================

local function InitDB()
    if not ADHDBiS_LootDB.sessions then
        ADHDBiS_LootDB.sessions = {}
    end
    -- Load saved filters or apply defaults
    if ADHDBiS_LootDB.lootFilters then
        for k, v in pairs(FILTER_DEFAULTS) do
            if ADHDBiS_LootDB.lootFilters[k] ~= nil then
                lootFilters[k] = ADHDBiS_LootDB.lootFilters[k]
            else
                lootFilters[k] = v
            end
        end
    end
end

local function SaveFilters()
    ADHDBiS_LootDB.lootFilters = {}
    for k, v in pairs(lootFilters) do
        ADHDBiS_LootDB.lootFilters[k] = v
    end
end

-- Get current instance name for session labeling
local function GetInstanceName()
    local name, instanceType, difficultyID, difficultyName = GetInstanceInfo()
    if name and name ~= "" then
        local label = name
        if difficultyName and difficultyName ~= "" then
            label = label .. " (" .. difficultyName .. ")"
        end
        return label
    end
    return nil
end

local function CreateNewSession(name)
    InitDB()
    local instName = name or (date("%Y-%m-%d %H:%M") .. " " .. (GetInstanceName() or ""))
    local session = {
        name = instName,
        created = time(),
        instanceName = GetInstanceName(),
        bosses = {},
        items = {},
    }

    table.insert(ADHDBiS_LootDB.sessions, 1, session) -- newest first

    -- Trim to MAX_SESSIONS
    while #ADHDBiS_LootDB.sessions > MAX_SESSIONS do
        table.remove(ADHDBiS_LootDB.sessions)
    end

    currentSession = ADHDBiS_LootDB.sessions[1]
    selectedSessionIndex = 1
    isTracking = true
    UpdateSessionLabel()
    return session
end

local function GetOrCreateCurrentSession()
    InitDB()
    if currentSession then return currentSession end
    -- No auto-reuse of old sessions - always create fresh
    return CreateNewSession()
end

function UpdateSessionLabel()
    if currentSession then
        local itemCount = #(currentSession.items or {})
        local label = (currentSession.name or "Unknown") .. " (" .. itemCount .. " items)"
        sessionBtnLabel:SetText(label)
    else
        sessionBtnLabel:SetText("No sessions")
    end
end

local function UpdateStatus()
    if isTracking then
        local enc = currentEncounter and ("|cFFFFD100" .. currentEncounter.name .. "|r") or "waiting"
        local itemCount = currentSession and #(currentSession.items or {}) or 0
        statusText:SetText("|cFF00FF00Tracking|r | " .. enc .. " | " .. itemCount .. " items")
    else
        statusText:SetText("|cFFFF4444Not tracking|r | Enter a raid or dungeon to start")
    end
end

-- ============================================================
-- SESSION POPUP: Continue or New Session
-- ============================================================

StaticPopupDialogs["ADHDBIS_SESSION_CHOICE"] = {
    text = "ADHDBiS: You have an existing session for\n|cFFFFD100%s|r\nwith %s items.\n\nContinue recording into that session or start a new one?",
    button1 = "Continue",
    button2 = "New Session",
    OnAccept = function()
        -- Continue: reuse existing session
        if pendingInstanceEntry then
            currentSession = pendingInstanceEntry.session
            selectedSessionIndex = pendingInstanceEntry.sessionIndex
            isTracking = true
            local sessionName = currentSession.name or "Unknown"
            pendingInstanceEntry = nil
            print("|cFF9482C9ADHDBiS:|r Continuing session: |cFFFFFFFF" .. sessionName .. "|r")
            UpdateSessionLabel()
            UpdateStatus()
            if lootFrame and lootFrame:IsShown() then RefreshLootGrid() end
        end
    end,
    OnCancel = function()
        -- New Session
        if pendingInstanceEntry then
            local instLabel = pendingInstanceEntry.instanceLabel
            pendingInstanceEntry = nil
            CreateNewSession()
            isTracking = true
            print("|cFF9482C9ADHDBiS:|r New loot session for " .. (instLabel or "instance") .. ".")
            UpdateStatus()
            if lootFrame and lootFrame:IsShown() then RefreshLootGrid() end
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = false,
    preferredIndex = 3,
}

-- ============================================================
-- INSTANCE ENTRY HANDLER
-- ============================================================

local lastInstanceEntryTime = 0

local function HandleInstanceEntry(instanceType)
    -- Guard against double-firing (PLAYER_ENTERING_WORLD + ZONE_CHANGED_NEW_AREA)
    if (time() - lastInstanceEntryTime) < 3 then return end
    lastInstanceEntryTime = time()

    InitDB()
    local instLabel = GetInstanceName() or "Unknown"
    local typeLabel = (instanceType == "raid") and "raid" or "dungeon"

    -- Check if there's a recent session for the same instance with items
    local matchSession, matchIndex
    if ADHDBiS_LootDB.sessions then
        for i, session in ipairs(ADHDBiS_LootDB.sessions) do
            if session.instanceName and session.instanceName == instLabel
                and session.items and #session.items > 0 then
                matchSession = session
                matchIndex = i
                break
            end
        end
    end

    if matchSession then
        -- Found existing session for same instance - ask user
        pendingInstanceEntry = {
            session = matchSession,
            sessionIndex = matchIndex,
            instanceLabel = instLabel,
        }
        -- Pause tracking while popup is up
        isTracking = false
        StaticPopup_Show("ADHDBIS_SESSION_CHOICE", instLabel, tostring(#matchSession.items))
    else
        -- No existing session for this instance - always create new
        CreateNewSession()
        isTracking = true
        print("|cFF9482C9ADHDBiS:|r Entered " .. typeLabel .. " - Loot Tracker active.")
        UpdateStatus()
        if lootFrame and lootFrame:IsShown() then RefreshLootGrid() end
    end
end

-- ============================================================
-- LOOT RECORDING
-- ============================================================

local function RecordLootItem(itemID, itemLink, bossName, playerName)
    local session = GetOrCreateCurrentSession()
    if not session then return end

    bossName = bossName or "Trash"
    playerName = playerName or UnitName("player")

    -- Add boss to list if new
    local bossFound = false
    for _, b in ipairs(session.bosses) do
        if b == bossName then bossFound = true break end
    end
    if not bossFound then
        table.insert(session.bosses, bossName)
    end

    -- Get item details from link (not base itemID) for accurate quality/ilvl
    local quality = GetItemQualityFromLink(itemLink)
    local ilvl = GetItemLevelFromLink(itemLink)
    local equipSlot = GetItemEquipSlot(itemID)
    local track, trackStep = GetGearTrack(ilvl)

    local category = GetItemCategory(itemID)

    local entry = {
        itemID = itemID,
        itemLink = itemLink,
        boss = bossName,
        player = playerName,
        quality = quality,
        ilvl = ilvl,
        track = track,
        trackStep = trackStep,
        equipSlot = equipSlot,
        category = category,
        timestamp = time(),
    }

    table.insert(session.items, entry)
    UpdateSessionLabel()

    -- Sound alert for epic+ items
    if quality >= 5 then
        -- Legendary: epic fanfare
        PlaySound(8960) -- SOUNDKIT.UI_LEGENDARY_LOOT_TOAST
    elseif quality >= 4 then
        -- Epic: notable sound
        PlaySound(31578) -- SOUNDKIT.UI_EPIC_LOOT_TOAST
    end

    -- Chat notification with player name, ilvl and track
    local displayLink = itemLink or ("[Item:" .. itemID .. "]")
    local playerStr = (playerName == UnitName("player")) and "|cFF00FF00You|r" or ("|cFFFFFFFF" .. playerName .. "|r")
    local ilvlStr = (ilvl and ilvl > 0) and (" |cFFFFFFFF(" .. ilvl .. ")|r") or ""
    local trackStr = (track and track ~= "") and (" |cFF888888" .. track .. " " .. trackStep .. "|r") or ""
    local upgradeStr = IsUpgradeForPlayer(itemID, ilvl) and " |cFF00FF00UPGRADE!|r" or ""
    print("|cFF9482C9ADHDBiS Loot:|r " .. displayLink .. ilvlStr .. trackStr .. upgradeStr .. " -> " .. playerStr .. " from |cFFFFD100" .. bossName .. "|r")

    -- Refresh grid if visible
    if lootFrame:IsShown() then
        RefreshLootGrid()
    end
end

-- ============================================================
-- REFRESH LOOT GRID
-- ============================================================

function RefreshLootGrid()
    HideAllLootGridCells()
    HideAllLootHeaders()

    lootScrollChild:SetWidth(lootFrame:GetWidth() - 42)

    if not currentSession or not currentSession.items or #currentSession.items == 0 then
        -- Show empty message
        local hdr = GetLootSectionHeader(1)
        hdr.text:SetText("|cFF888888No loot recorded yet. Enter a raid or dungeon to start tracking.|r")
        hdr:SetPoint("TOPLEFT", lootScrollChild, "TOPLEFT", 0, 0)
        hdr:SetPoint("RIGHT", lootScrollChild, "RIGHT", 0, 0)
        lootScrollChild:SetHeight(20)
        UpdateStatus()
        return
    end

    -- Group items by boss
    local bossList = currentSession.bosses or {}
    local itemsByBoss = {}
    for _, item in ipairs(currentSession.items) do
        local boss = item.boss or "Trash"
        if not itemsByBoss[boss] then itemsByBoss[boss] = {} end
        table.insert(itemsByBoss[boss], item)
    end

    -- Check for items from bosses not in bossList (e.g. "Trash")
    for boss, _ in pairs(itemsByBoss) do
        local found = false
        for _, b in ipairs(bossList) do
            if b == boss then found = true break end
        end
        if not found then
            table.insert(bossList, boss)
        end
    end

    local headerIndex = 0
    local cellIndex = 0
    local yOffset = 0
    local frameWidth = lootScrollChild:GetWidth()
    local cols = math.floor(frameWidth / (GRID_CELL_WIDTH + GRID_PADDING))
    if cols < 1 then cols = 1 end

    for _, bossName in ipairs(bossList) do
        local bossItems = itemsByBoss[bossName]
        if bossItems and #bossItems > 0 then
            -- Boss header
            headerIndex = headerIndex + 1
            local hdr = GetLootSectionHeader(headerIndex)
            hdr.text:SetText("|cFFFFD100" .. bossName .. "|r  |cFF888888(" .. #bossItems .. " items)|r")
            hdr:SetPoint("TOPLEFT", lootScrollChild, "TOPLEFT", 0, -yOffset)
            hdr:SetPoint("RIGHT", lootScrollChild, "RIGHT", 0, 0)
            yOffset = yOffset + 22

            -- Grid cells for this boss
            local sectionStart = cellIndex
            local visibleCount = 0
            for _, item in ipairs(bossItems) do
                -- Apply filters: category + quality
                local cat = item.category or GetItemCategory(item.itemID)
                local passCategory = lootFilters[cat] ~= false
                local passQuality = not lootFilters.epicOnly or (item.quality and item.quality >= 4)
                if passCategory and passQuality then
                cellIndex = cellIndex + 1
                local cell = GetLootGridCell(cellIndex)

                cell.icon:SetTexture(GetItemIcon(item.itemID))

                -- Quality border color
                local qColor = QUALITY_COLORS[item.quality] or QUALITY_COLORS[3]
                cell.borderTex:SetColorTexture(qColor[1], qColor[2], qColor[3], 1)

                -- Upgrade arrow (green up arrow if ilvl > equipped)
                local ilvl = item.ilvl or 0
                local isUpgrade = IsUpgradeForPlayer(item.itemID, ilvl)
                cell.isUpgrade = isUpgrade
                cell.upgradeArrow:SetText(isUpgrade and "|cFF00FF00^|r" or "")

                -- Wishlist star
                local wishlisted = IsWishlisted(item.itemID)
                cell.isWishlisted = wishlisted
                cell.wishlistStar:SetText(wishlisted and "|cFFFFD100*|r" or "")

                -- Line 1: ilvl
                if ilvl > 0 then
                    local ilvlColor = isUpgrade and "|cFF00FF00" or "|cFFFFFFFF"
                    cell.ilvlLabel:SetText(ilvlColor .. ilvl .. "|r")
                else
                    cell.ilvlLabel:SetText(item.equipSlot or "")
                end

                -- Line 2: gear track (e.g. "Hero 3/6")
                local track = item.track or ""
                local trackStep = item.trackStep or ""
                if track ~= "" then
                    cell.trackLabel:SetText(track .. " " .. trackStep)
                else
                    cell.trackLabel:SetText(item.equipSlot or "")
                end

                -- Line 3: player name
                local pName = item.player or ""
                if pName == UnitName("player") then
                    cell.playerLabel:SetText("|cFF00FF00You|r")
                elseif pName ~= "" then
                    cell.playerLabel:SetText(pName)
                else
                    cell.playerLabel:SetText("")
                end

                -- Store link for accurate tooltip
                cell.storedLink = item.itemLink
                cell.itemID = item.itemID

                -- Position cell in grid
                local idx = cellIndex - sectionStart
                local row = math.floor((idx - 1) / cols)
                local col = (idx - 1) % cols
                cell:ClearAllPoints()
                cell:SetPoint("TOPLEFT", lootScrollChild, "TOPLEFT",
                    col * (GRID_CELL_WIDTH + GRID_PADDING),
                    -(row * (GRID_CELL_HEIGHT + GRID_PADDING)) - yOffset)
                visibleCount = visibleCount + 1
                end -- end filter
            end

            local secCount = cellIndex - sectionStart
            if secCount == 0 then
                -- No visible items for this boss, hide the header
                hdr:Hide()
                headerIndex = headerIndex - 1
                yOffset = yOffset - 22
            else
                -- Update header with visible/total count
                hdr.text:SetText("|cFFFFD100" .. bossName .. "|r  |cFF888888(" .. secCount .. " items)|r")
                local secRows = math.ceil(secCount / cols)
                yOffset = yOffset + secRows * (GRID_CELL_HEIGHT + GRID_PADDING) + 6
            end
        end
    end

    lootScrollChild:SetHeight(math.max(1, yOffset))
    lootScrollFrame:SetVerticalScroll(0)
    UpdateStatus()
end

-- ============================================================
-- EVENT HANDLING
-- ============================================================

local lootEventFrame = CreateFrame("Frame")

-- Track the last boss that was killed
local lastEncounterName = nil
local lastEncounterTime = 0

local function OnEvent(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        InitDB()

        -- Restore window position/size
        local db = ADHDBiS_LootDB
        if db.lootWindowPoint then
            local p = db.lootWindowPoint
            lootFrame:ClearAllPoints()
            lootFrame:SetPoint(p[1], UIParent, p[3], p[4], p[5])
        end
        if db.lootWindowWidth then
            lootFrame:SetSize(db.lootWindowWidth, db.lootWindowHeight or 400)
        end

        UpdateSessionLabel()
        UpdateFilterButtonText()

        -- Check if we're in a raid or dungeon instance
        local _, instanceType = IsInInstance()
        if instanceType == "raid" or instanceType == "party" then
            HandleInstanceEntry(instanceType)
        elseif db.sessions and #db.sessions > 0 then
            -- Outside instance: load most recent session for viewing
            currentSession = db.sessions[1]
            selectedSessionIndex = 1
        end

        UpdateStatus()

    elseif event == "ENCOUNTER_START" then
        local encounterID, encounterName = ...
        currentEncounter = { name = encounterName, id = encounterID }
        UpdateStatus()

    elseif event == "ENCOUNTER_END" then
        local encounterID, encounterName, difficultyID, groupSize, success = ...
        if success == 1 then
            lastEncounterName = encounterName
            lastEncounterTime = time()
        end
        currentEncounter = nil
        UpdateStatus()

    elseif event == "CHAT_MSG_LOOT" then
        if not isTracking then return end

        local msg = ...
        if not msg then return end

        -- Check if the message is a secret value (12.x)
        if issecretvalue and issecretvalue(msg) then return end

        -- Parse item link from message
        local link = msg:match("|Hitem:[^|]+|h[^|]+|h")
        if not link then return end

        local itemID = tonumber(link:match("item:(%d+)"))
        if not itemID then return end

        local _, _, quality = GetItemInfo(itemID)
        if quality and quality < 3 then return end -- Skip below rare

        -- Parse player name: "PlayerName receives loot: [Item]" or "You receive loot: [Item]"
        local playerName = UnitName("player")
        local looter = msg:match("^(.+) receives? loot")
        if looter then
            -- Strip realm name if present
            looter = looter:match("^([^-]+)") or looter
            playerName = looter
        end

        -- Determine boss
        local bossName = "Trash"
        if lastEncounterName and (time() - lastEncounterTime) < 60 then
            bossName = lastEncounterName
        end

        -- Deduplicate: same item + same player within 5 seconds (handles WoW sending duplicate chat msgs)
        if currentSession then
            for j = #currentSession.items, math.max(1, #currentSession.items - 10), -1 do
                local existing = currentSession.items[j]
                if existing and existing.itemID == itemID
                    and existing.player == playerName
                    and (time() - existing.timestamp) < 5 then
                    return -- Exact duplicate, skip
                end
            end
        end

        RecordLootItem(itemID, link, bossName, playerName)

    elseif event == "ZONE_CHANGED_NEW_AREA" then
        local _, instanceType = IsInInstance()
        if instanceType == "raid" or instanceType == "party" then
            -- Always handle instance entry (new session or prompt)
            HandleInstanceEntry(instanceType)
        else
            if isTracking then
                isTracking = false
                currentEncounter = nil
                UpdateStatus()
            end
        end
    end
end

lootEventFrame:SetScript("OnEvent", OnEvent)
lootEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
lootEventFrame:RegisterEvent("ENCOUNTER_START")
lootEventFrame:RegisterEvent("ENCOUNTER_END")
lootEventFrame:RegisterEvent("CHAT_MSG_LOOT")
lootEventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")

-- ============================================================
-- TOGGLE / COMMANDS (exposed to main addon via ns)
-- ============================================================

function ns.ToggleLootTracker(subCmd)
    subCmd = subCmd or ""

    -- /adhd loot new [optional name]
    if subCmd == "new" or subCmd:find("^new ") then
        local customName = subCmd:match("^new (.+)")
        local sessionName
        if customName and customName:trim() ~= "" then
            sessionName = date("%Y-%m-%d %H:%M") .. " " .. customName:trim()
        else
            local instName = GetInstanceName()
            sessionName = date("%Y-%m-%d %H:%M") .. " " .. (instName or "Manual Session")
        end
        CreateNewSession(sessionName)
        isTracking = true
        print("|cFF9482C9ADHDBiS:|r New loot session: |cFFFFFFFF" .. sessionName .. "|r")
        UpdateStatus()
        if lootFrame:IsShown() then RefreshLootGrid() end
        return
    end

    -- /adhd loot stop
    if subCmd == "stop" then
        isTracking = false
        currentEncounter = nil
        print("|cFF9482C9ADHDBiS:|r Loot tracking stopped.")
        UpdateStatus()
        return
    end

    -- /adhd loot start (resume)
    if subCmd == "start" then
        if not currentSession then
            local instName = GetInstanceName()
            CreateNewSession(date("%Y-%m-%d %H:%M") .. " " .. (instName or "Manual Session"))
        end
        isTracking = true
        print("|cFF9482C9ADHDBiS:|r Loot tracking started.")
        UpdateStatus()
        return
    end

    -- /adhd loot summary - print session summary to chat
    if subCmd == "summary" then
        if not currentSession or not currentSession.items or #currentSession.items == 0 then
            print("|cFF9482C9ADHDBiS:|r No loot in current session.")
            return
        end
        print("|cFF9482C9ADHDBiS:|r --- Session: |cFFFFFFFF" .. (currentSession.name or "?") .. "|r ---")
        -- Count items per player
        local playerItems = {}
        for _, item in ipairs(currentSession.items) do
            local p = item.player or "Unknown"
            playerItems[p] = (playerItems[p] or 0) + 1
        end
        for player, count in pairs(playerItems) do
            local color = (player == UnitName("player")) and "|cFF00FF00" or "|cFFFFFFFF"
            print("  " .. color .. player .. "|r: " .. count .. " items")
        end
        -- List items by boss
        for _, bossName in ipairs(currentSession.bosses or {}) do
            print("  |cFFFFD100" .. bossName .. ":|r")
            for _, item in ipairs(currentSession.items) do
                if item.boss == bossName then
                    local link = item.itemLink or ("[" .. item.itemID .. "]")
                    local ilvlStr = (item.ilvl and item.ilvl > 0) and (" " .. item.ilvl) or ""
                    local trackStr = (item.track and item.track ~= "") and (" " .. item.track .. " " .. item.trackStep) or ""
                    local playerStr = item.player or "?"
                    print("    " .. link .. ilvlStr .. trackStr .. " -> " .. playerStr)
                end
            end
        end
        return
    end

    -- /adhd loot wishlist
    if subCmd == "wishlist" then
        if not ADHDBiS_LootDB.wishlist or not next(ADHDBiS_LootDB.wishlist) then
            print("|cFF9482C9ADHDBiS:|r Wishlist is empty. Right-click items in loot grid to bookmark them.")
            return
        end
        print("|cFF9482C9ADHDBiS:|r --- Wishlist ---")
        for itemID, _ in pairs(ADHDBiS_LootDB.wishlist) do
            local name, link = C_Item.GetItemInfo(itemID)
            print("  |cFFFFD100*|r " .. (link or name or ("Item " .. itemID)))
        end
        return
    end

    -- /adhd loot help
    if subCmd == "help" then
        print("|cFF9482C9ADHDBiS Loot Tracker|r commands:")
        print("  |cFFFFFFFF/adhd loot|r - Toggle loot window")
        print("  |cFFFFFFFF/adhd loot new|r - New session (auto-names with instance)")
        print("  |cFFFFFFFF/adhd loot new My Raid|r - New session with custom name")
        print("  |cFFFFFFFF/adhd loot start|r - Resume tracking")
        print("  |cFFFFFFFF/adhd loot stop|r - Pause tracking")
        print("  |cFFFFFFFF/adhd loot summary|r - Print session summary to chat")
        print("  |cFFFFFFFF/adhd loot wishlist|r - Show wishlisted items")
        print("  |cFFFFFFFF/adhd loot help|r - Show this help")
        print("  |cFF888888Grid: Right-click = Wishlist | Shift+Click = Preview | Ctrl+Click = Chat|r")
        return
    end

    -- Default: toggle window
    if lootFrame:IsShown() then
        lootFrame:Hide()
    else
        -- Load session from saved data if we don't have one
        if not currentSession then
            InitDB()
            local sessions = ADHDBiS_LootDB.sessions
            if sessions and #sessions > 0 then
                currentSession = sessions[1]
                selectedSessionIndex = 1
            end
        end
        UpdateSessionLabel()
        UpdateStatus()
        lootFrame:Show()
        RefreshLootGrid()
    end
end
