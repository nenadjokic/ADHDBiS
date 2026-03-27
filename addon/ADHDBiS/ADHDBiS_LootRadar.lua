-- ADHDBiS LootRadar: Scan party loot after M+ and detect upgrades
-- ================================================================

local addonName, ns = ...

ADHDBiS_LootRadarDB = ADHDBiS_LootRadarDB or {}

local EQUIP_LOC_TO_SLOT = {
    INVTYPE_HEAD = 1, INVTYPE_NECK = 2, INVTYPE_SHOULDER = 3,
    INVTYPE_CHEST = 5, INVTYPE_ROBE = 5, INVTYPE_WAIST = 6,
    INVTYPE_LEGS = 7, INVTYPE_FEET = 8, INVTYPE_WRIST = 9,
    INVTYPE_HAND = 10, INVTYPE_FINGER = 11, INVTYPE_TRINKET = 13,
    INVTYPE_CLOAK = 15, INVTYPE_WEAPON = 16, INVTYPE_2HWEAPON = 16,
    INVTYPE_WEAPONMAINHAND = 16, INVTYPE_WEAPONOFFHAND = 17,
    INVTYPE_HOLDABLE = 17, INVTYPE_SHIELD = 17, INVTYPE_RANGED = 16,
}

local SLOT_NAMES = {
    [1] = "Head", [2] = "Neck", [3] = "Shoulders", [5] = "Chest",
    [6] = "Waist", [7] = "Legs", [8] = "Feet", [9] = "Wrist",
    [10] = "Hands", [11] = "Ring 1", [12] = "Ring 2",
    [13] = "Trinket 1", [14] = "Trinket 2", [15] = "Back",
    [16] = "Main Hand", [17] = "Off Hand",
}

local ALL_GEAR_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17 }

-- Runtime state
local partySnapshots = {}   -- [unitName] = { [slotID] = { link, ilvl, itemID } }
local detectedUpgrades = {} -- { { looter, itemLink, itemID, ilvl, reason, slotName } }
local mythicPlusActive = false
local inDungeon = false      -- true when in any dungeon (M0, M+, heroic, etc.)
local snapshotTaken = false  -- prevents re-snapshotting on every zone change
local inspectQueue = {}
local inspectCallback = nil -- "snapshot" or "compare"
local inspectRetries = {}   -- [unit] = retry count

-- ============================================================
-- HELPERS
-- ============================================================

local function GetDB()
    if not ADHDBiS_LootRadarDB.windowPoint then
        ADHDBiS_LootRadarDB.windowPoint = nil
    end
    if ADHDBiS_LootRadarDB.messageMode == nil then
        ADHDBiS_LootRadarDB.messageMode = "party" -- "whisper" or "party"
    end
    return ADHDBiS_LootRadarDB
end

local function GetPlayerSpec()
    local specIndex = GetSpecialization()
    if specIndex then
        local _, specName = GetSpecializationInfo(specIndex)
        return specName
    end
    return nil
end

local function IsBiSForSpec(itemID)
    if not itemID or not ADHDBiS_Data then return false, nil end
    local playerClass = UnitClass("player")
    local specName = GetPlayerSpec()
    if not playerClass or not specName then return false, nil end
    if not ADHDBiS_Data.classes or not ADHDBiS_Data.classes[playerClass] then return false, nil end
    local specData = ADHDBiS_Data.classes[playerClass][specName]
    if not specData then return false, nil end
    for sourceName, data in pairs(specData) do
        if type(data) == "table" and data.gear then
            -- Check M+ BiS first (more relevant)
            if data.gear.mythicplus then
                for _, item in ipairs(data.gear.mythicplus) do
                    if item.itemID == itemID then
                        return true, "M+ BiS"
                    end
                end
            end
            if data.gear.raid then
                for _, item in ipairs(data.gear.raid) do
                    if item.itemID == itemID then
                        return true, "Raid BiS"
                    end
                end
            end
        end
    end
    return false, nil
end

local function IsUpgradeForPlayer(itemID, itemIlvl)
    if not itemID or not itemIlvl or itemIlvl == 0 then return false, 0, nil end
    local _, _, _, equipLoc = GetItemInfoInstant(itemID)
    if not equipLoc or equipLoc == "" then return false, 0, nil end
    local slotID = EQUIP_LOC_TO_SLOT[equipLoc]
    if not slotID then return false, 0, nil end
    local slotsToCheck = { slotID }
    if equipLoc == "INVTYPE_FINGER" then slotsToCheck = { 11, 12 } end
    if equipLoc == "INVTYPE_TRINKET" then slotsToCheck = { 13, 14 } end
    local lowestEquipped = 99999
    local lowestSlot = slotID
    for _, sid in ipairs(slotsToCheck) do
        local equippedLink = GetInventoryItemLink("player", sid)
        if equippedLink then
            local eIlvl = GetDetailedItemLevelInfo(equippedLink)
            if eIlvl and eIlvl < lowestEquipped then
                lowestEquipped = eIlvl
                lowestSlot = sid
            end
        else
            lowestEquipped = 0
            lowestSlot = sid
        end
    end
    if itemIlvl > lowestEquipped then
        return true, itemIlvl - lowestEquipped, SLOT_NAMES[lowestSlot] or "?"
    end
    return false, 0, nil
end

-- ============================================================
-- GEAR SNAPSHOT
-- ============================================================

local function SnapshotUnit(unit)
    local snapshot = {}
    for _, slotID in ipairs(ALL_GEAR_SLOTS) do
        local link = GetInventoryItemLink(unit, slotID)
        if link then
            local itemID = GetItemInfoInstant(link)
            if itemID then
                local ilvl = GetDetailedItemLevelInfo(link)
                snapshot[slotID] = { link = link, ilvl = ilvl or 0, itemID = itemID }
            end
        end
    end
    return snapshot
end

local function SnapshotAllParty()
    partySnapshots = {}
    -- Snapshot self
    partySnapshots[UnitName("player")] = SnapshotUnit("player")
    -- Queue inspect for party members
    inspectQueue = {}
    inspectRetries = {}
    inspectCallback = "snapshot"
    for i = 1, 4 do
        local unit = "party" .. i
        if UnitExists(unit) and UnitIsConnected(unit) then
            table.insert(inspectQueue, unit)
        end
    end
    ProcessInspectQueue()
end

function ProcessInspectQueue()
    if #inspectQueue == 0 then
        if inspectCallback == "snapshot" then
            -- Silently complete - initial snapshot message already printed in CheckDungeonStatus
            inspectCallback = nil
        elseif inspectCallback == "compare" then
            CompareAndShowResults()
        end
        return
    end
    local unit = inspectQueue[1]
    if UnitExists(unit) and UnitIsConnected(unit) and CanInspect(unit) then
        table.remove(inspectQueue, 1)
        inspectRetries[unit] = nil
        NotifyInspect(unit)
    else
        local retries = (inspectRetries[unit] or 0) + 1
        if retries >= 3 then
            table.remove(inspectQueue, 1)
            inspectRetries[unit] = nil
        else
            inspectRetries[unit] = retries
        end
        C_Timer.After(0.5, ProcessInspectQueue)
    end
end

-- ============================================================
-- POST-COMPLETION COMPARISON
-- ============================================================

local function ComparePartyGear()
    inspectQueue = {}
    inspectRetries = {}
    inspectCallback = "compare"
    -- Re-snapshot self first
    partySnapshots["_new_" .. UnitName("player")] = SnapshotUnit("player")
    -- Queue inspect for party members
    for i = 1, 4 do
        local unit = "party" .. i
        if UnitExists(unit) and UnitIsConnected(unit) then
            table.insert(inspectQueue, unit)
        end
    end
    ProcessInspectQueue()
end

function CompareAndShowResults()
    detectedUpgrades = {}
    local playerName = UnitName("player")

    for name, oldSnap in pairs(partySnapshots) do
        if name:sub(1, 5) == "_new_" then
            -- skip new snapshots
        elseif name == playerName then
            -- skip self
        else
            local newSnap = partySnapshots["_new_" .. name]
            if newSnap then
                -- Compare old vs new gear for this party member
                for _, slotID in ipairs(ALL_GEAR_SLOTS) do
                    local old = oldSnap[slotID]
                    local new = newSnap[slotID]
                    -- Only detect as new loot if:
                    -- 1. New item exists AND old item existed (prevents false positives from failed inspects)
                    -- 2. Item IDs are different (they actually changed gear)
                    if new and old and old.itemID ~= new.itemID then
                        -- This player got a new item in this slot
                        local newItemID = new.itemID
                        local newIlvl = new.ilvl
                        local newLink = new.link

                        -- Check if it's an upgrade for us
                        local isBiS, bisType = IsBiSForSpec(newItemID)
                        local isUpgrade, ilvlDiff, slotName = IsUpgradeForPlayer(newItemID, newIlvl)

                        -- Skip BiS if we already have same item at same or higher ilvl
                        if isBiS and not isUpgrade then
                            local _, _, _, eqLoc = GetItemInfoInstant(newItemID)
                            if eqLoc then
                                local eqSlot = EQUIP_LOC_TO_SLOT[eqLoc]
                                if eqSlot then
                                    local checkSlots = { eqSlot }
                                    if eqLoc == "INVTYPE_FINGER" then checkSlots = { 11, 12 } end
                                    if eqLoc == "INVTYPE_TRINKET" then checkSlots = { 13, 14 } end
                                    for _, sid in ipairs(checkSlots) do
                                        local eLink = GetInventoryItemLink("player", sid)
                                        if eLink then
                                            local eID = GetItemInfoInstant(eLink)
                                            local eIlvl = GetDetailedItemLevelInfo(eLink) or 0
                                            if eID == newItemID and eIlvl >= newIlvl then
                                                isBiS = false
                                                break
                                            end
                                        end
                                    end
                                end
                            end
                        end

                        if isBiS then
                            table.insert(detectedUpgrades, {
                                looter = name,
                                itemLink = newLink,
                                itemID = newItemID,
                                ilvl = newIlvl,
                                reason = "bis",
                                reasonText = "|cFFFFD100" .. bisType .. " for " .. (GetPlayerSpec() or "your spec") .. "!|r",
                                slotName = slotName or SLOT_NAMES[slotID] or "?",
                            })
                        elseif isUpgrade then
                            table.insert(detectedUpgrades, {
                                looter = name,
                                itemLink = newLink,
                                itemID = newItemID,
                                ilvl = newIlvl,
                                reason = "ilvl",
                                reasonText = "|cFF00FF00+" .. ilvlDiff .. " ilvl upgrade|r (" .. (slotName or "?") .. ")",
                                slotName = slotName or SLOT_NAMES[slotID] or "?",
                            })
                        end
                    end
                end
            end
        end
    end

    -- Also check loot from CHAT_MSG_LOOT that wasn't equipped
    -- (handled via lootedItems table)

    if #detectedUpgrades > 0 then
        ShowLootRadarPanel()
    end
    -- Don't spam "No upgrades detected" - silently do nothing if no upgrades found
end

-- ============================================================
-- CHAT_MSG_LOOT TRACKING (secondary source)
-- ============================================================

local lootedItems = {} -- { { looter, itemLink, itemID, ilvl } }

local function OnLootMessage(msg)
    if not inDungeon then return end
    -- Parse "PlayerName receives loot: [Item Link]"
    -- or "You receive loot: [Item Link]"
    local playerName, itemLink = msg:match("(.+) receives loot: (.+)")
    if not playerName then
        itemLink = msg:match("You receive loot: (.+)")
        if itemLink then
            playerName = UnitName("player")
        end
    end
    if not playerName or not itemLink then return end

    -- Clean up item link
    itemLink = itemLink:match("|c.-|r") or itemLink
    local itemID = GetItemInfoInstant(itemLink)
    if not itemID then return end
    local ilvl = GetDetailedItemLevelInfo(itemLink) or 0

    -- Skip own loot
    if playerName == UnitName("player") then return end

    -- Check upgrade potential
    local isBiS, bisType = IsBiSForSpec(itemID)
    local isUpgrade, ilvlDiff, slotName = IsUpgradeForPlayer(itemID, ilvl)

    -- If BiS but we already have the same item equipped at same or higher ilvl, skip
    if isBiS and not isUpgrade then
        local _, _, _, equipLoc = GetItemInfoInstant(itemID)
        if equipLoc then
            local slotID = EQUIP_LOC_TO_SLOT[equipLoc]
            if slotID then
                local slotsToCheck = { slotID }
                if equipLoc == "INVTYPE_FINGER" then slotsToCheck = { 11, 12 } end
                if equipLoc == "INVTYPE_TRINKET" then slotsToCheck = { 13, 14 } end
                for _, sid in ipairs(slotsToCheck) do
                    local equippedLink = GetInventoryItemLink("player", sid)
                    if equippedLink then
                        local equippedID = GetItemInfoInstant(equippedLink)
                        local equippedIlvl = GetDetailedItemLevelInfo(equippedLink) or 0
                        if equippedID == itemID and equippedIlvl >= ilvl then
                            return -- already have same item at same or higher ilvl
                        end
                    end
                end
            end
        end
    end

    if isBiS or isUpgrade then
        local upgrade = {
            looter = playerName,
            itemLink = itemLink,
            itemID = itemID,
            ilvl = ilvl,
            slotName = slotName or "?",
        }
        if isBiS then
            upgrade.reason = "bis"
            upgrade.reasonText = "|cFFFFD100" .. bisType .. " for " .. (GetPlayerSpec() or "your spec") .. "!|r"
        else
            upgrade.reason = "ilvl"
            upgrade.reasonText = "|cFF00FF00+" .. ilvlDiff .. " ilvl upgrade|r (" .. (slotName or "?") .. ")"
        end

        -- Avoid duplicates
        local dominated = false
        for _, existing in ipairs(detectedUpgrades) do
            if existing.looter == upgrade.looter and existing.itemID == upgrade.itemID then
                dominated = true
                break
            end
        end
        if not dominated then
            table.insert(detectedUpgrades, upgrade)
            ShowLootRadarPanel()
        end
    end
end

-- ============================================================
-- UI: LOOT RADAR PANEL
-- ============================================================

local radarFrame = CreateFrame("Frame", "ADHDBiSLootRadarFrame", UIParent, "BackdropTemplate")
radarFrame:SetSize(440, 300)
radarFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
radarFrame:SetFrameStrata("DIALOG")
radarFrame:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
})
radarFrame:SetBackdropColor(0.05, 0.05, 0.08, 0.95)
radarFrame:SetBackdropBorderColor(0.4, 0.8, 0.3, 0.9)
radarFrame:SetMovable(true)
radarFrame:EnableMouse(true)
radarFrame:RegisterForDrag("LeftButton")
radarFrame:SetClampedToScreen(true)
radarFrame:SetScript("OnDragStart", radarFrame.StartMoving)
radarFrame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint()
    ADHDBiS_LootRadarDB.windowPoint = { p, nil, rp, x, y }
end)
radarFrame:SetResizable(true)
radarFrame:SetResizeBounds(440, 100, 440, 600)
radarFrame:Hide()

-- Resize handle
local resizeHandle = CreateFrame("Button", nil, radarFrame)
resizeHandle:SetSize(16, 16)
resizeHandle:SetPoint("BOTTOMRIGHT", radarFrame, "BOTTOMRIGHT", 0, 0)
resizeHandle:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
resizeHandle:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
resizeHandle:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
resizeHandle:SetScript("OnMouseDown", function()
    radarFrame:StartSizing("BOTTOMRIGHT")
end)
resizeHandle:SetScript("OnMouseUp", function()
    radarFrame:StopMovingOrSizing()
end)

-- Title
local titleBg = radarFrame:CreateTexture(nil, "ARTWORK")
titleBg:SetHeight(24)
titleBg:SetPoint("TOPLEFT", radarFrame, "TOPLEFT", 4, -4)
titleBg:SetPoint("TOPRIGHT", radarFrame, "TOPRIGHT", -4, -4)
titleBg:SetColorTexture(0.1, 0.2, 0.1, 0.6)

local titleText = radarFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
titleText:SetPoint("TOPLEFT", radarFrame, "TOPLEFT", 12, -8)
titleText:SetText("|cFF9482C9ADHDBiS|r |cFF00FF00LootRadar|r")

-- Close button (safe - custom, no UIPanelCloseButton)
local closeBtn = CreateFrame("Button", nil, radarFrame)
closeBtn:SetSize(20, 20)
closeBtn:SetPoint("TOPRIGHT", radarFrame, "TOPRIGHT", -6, -6)
closeBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
closeBtn:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
closeBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight", "ADD")
closeBtn:SetScript("OnClick", function() radarFrame:Hide() end)

-- Message mode toggle
local modeBtn = CreateFrame("Button", nil, radarFrame, "UIPanelButtonTemplate")
modeBtn:SetSize(90, 20)
modeBtn:SetPoint("TOPRIGHT", closeBtn, "TOPLEFT", -5, 0)
modeBtn:SetScript("OnClick", function(self)
    local db = GetDB()
    if db.messageMode == "whisper" then
        db.messageMode = "party"
    else
        db.messageMode = "whisper"
    end
    self:SetText(db.messageMode == "whisper" and "Whisper" or "Party Chat")
end)

modeBtn:SetText("Party Chat") -- default text on creation

local modeLabelText = radarFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
modeLabelText:SetPoint("RIGHT", modeBtn, "LEFT", -5, 0)
modeLabelText:SetText("|cFF888888Mode:|r")

-- Status text (shown when no upgrades)
local statusText = radarFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
statusText:SetPoint("CENTER", radarFrame, "CENTER", 0, 0)
statusText:SetText("|cFF666666Waiting for M+ completion...|r")

-- Scroll frame for results
local scrollFrame = CreateFrame("ScrollFrame", "ADHDBiSLootRadarScroll", radarFrame, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", radarFrame, "TOPLEFT", 8, -32)
scrollFrame:SetPoint("BOTTOMRIGHT", radarFrame, "BOTTOMRIGHT", -28, 8)

local scrollChild = CreateFrame("Frame", nil, scrollFrame)
scrollChild:SetSize(1, 1)
scrollFrame:SetScrollChild(scrollChild)

-- Row pool
local rowPool = {}
local ROW_HEIGHT = 60

local function CreateResultRow(index)
    local row = CreateFrame("Frame", nil, scrollChild, "BackdropTemplate")
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
    row:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)
    row:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    row:SetBackdropColor(0.08, 0.08, 0.12, 0.8)
    row:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.5)

    -- Item icon
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(40, 40)
    icon:SetPoint("LEFT", row, "LEFT", 8, 0)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.icon = icon

    -- Icon quality border
    local iconBorder = row:CreateTexture(nil, "OVERLAY")
    iconBorder:SetSize(44, 44)
    iconBorder:SetPoint("CENTER", icon, "CENTER", 0, 0)
    iconBorder:SetTexture("Interface\\Common\\WhiteIconFrame")
    row.iconBorder = iconBorder

    -- Line 1: Looter + item link
    local line1 = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    line1:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, -2)
    line1:SetPoint("RIGHT", row, "RIGHT", -110, 0)
    line1:SetJustifyH("LEFT")
    line1:SetWordWrap(false)
    row.line1 = line1

    -- Line 2: Reason (BiS or ilvl upgrade)
    local line2 = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    line2:SetPoint("TOPLEFT", line1, "BOTTOMLEFT", 0, -3)
    line2:SetPoint("RIGHT", row, "RIGHT", -110, 0)
    line2:SetJustifyH("LEFT")
    row.line2 = line2

    -- Line 3: ilvl info
    local line3 = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    line3:SetPoint("TOPLEFT", line2, "BOTTOMLEFT", 0, -2)
    line3:SetPoint("RIGHT", row, "RIGHT", -110, 0)
    line3:SetJustifyH("LEFT")
    line3:SetTextColor(0.6, 0.6, 0.6)
    row.line3 = line3

    -- Send button
    local sendBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    sendBtn:SetSize(90, 24)
    sendBtn:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    sendBtn:SetText("Ask")
    row.sendBtn = sendBtn

    rowPool[index] = row
    return row
end

function ShowLootRadarPanel()
    local db = GetDB()

    -- Restore window position
    if db.windowPoint then
        local p = db.windowPoint
        radarFrame:ClearAllPoints()
        radarFrame:SetPoint(p[1], UIParent, p[3], p[4], p[5])
    end

    -- Update mode button
    modeBtn:SetText(db.messageMode == "whisper" and "Whisper" or "Party Chat")

    if #detectedUpgrades == 0 then
        statusText:SetText("|cFF666666No upgrades found from party loot.|r")
        statusText:Show()
        scrollFrame:Hide()
        radarFrame:SetHeight(100)
        radarFrame:Show()
        return
    end

    statusText:Hide()
    scrollFrame:Show()
    radarFrame:SetHeight(math.min(40 + #detectedUpgrades * ROW_HEIGHT, 400))

    -- Update scroll child width
    scrollChild:SetWidth(scrollFrame:GetWidth())

    for i, upgrade in ipairs(detectedUpgrades) do
        local row = rowPool[i] or CreateResultRow(i)

        -- Item icon
        local iconTexture = C_Item.GetItemIconByID(upgrade.itemID)
        row.icon:SetTexture(iconTexture or "Interface\\Icons\\INV_Misc_QuestionMark")

        -- Quality border color
        local _, _, quality = GetItemInfo(upgrade.itemLink or "")
        if quality then
            local r, g, b = GetItemQualityColor(quality)
            row.iconBorder:SetVertexColor(r, g, b, 1)
        else
            row.iconBorder:SetVertexColor(0.5, 0.5, 0.5, 1)
        end

        -- BiS items get green border on row
        if upgrade.reason == "bis" then
            row:SetBackdropBorderColor(0.2, 0.8, 0.2, 0.7)
        else
            row:SetBackdropBorderColor(0.3, 0.6, 0.3, 0.5)
        end

        -- Text
        row.line1:SetText("|cFFFFFF00" .. upgrade.looter .. "|r looted " .. (upgrade.itemLink or "[?]"))
        row.line2:SetText(upgrade.reasonText)
        row.line3:SetText("Item Level: " .. (upgrade.ilvl or "?"))

        -- Send button
        row.sendBtn:SetText(db.messageMode == "whisper" and "Whisper" or "Party")
        row.sent = false
        row.sendBtn:Enable()
        row.sendBtn:SetScript("OnClick", function(self)
            if row.sent then return end
            local mode = GetDB().messageMode
            local specName = GetPlayerSpec() or "my spec"
            local className = UnitClass("player") or "?"
            local itemStr = upgrade.itemLink or "[item]"

            if mode == "whisper" then
                local whisperMsg = "Hey! Nice " .. itemStr .. "! If you don't need it, would you mind trading it? It's an upgrade for my " .. specName .. " " .. className .. " :)"
                SendChatMessage(whisperMsg, "WHISPER", nil, upgrade.looter)
                print("|cFF9482C9ADHDBiS LootRadar:|r Whisper sent to |cFFFFFF00" .. upgrade.looter .. "|r")
            else
                local partyMsg = "Grats on the loot! If anyone doesn't need " .. itemStr .. ", I could use it for my " .. specName .. " " .. className .. "!"
                SendChatMessage(partyMsg, "PARTY")
                print("|cFF9482C9ADHDBiS LootRadar:|r Message sent to party chat")
            end

            row.sent = true
            self:SetText("|cFF00FF00Sent!|r")
            self:Disable()
        end)

        -- Tooltip on icon hover
        row:SetScript("OnEnter", function(self)
            if upgrade.itemLink then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink(upgrade.itemLink)
                GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row:EnableMouse(true)

        row:Show()
    end

    -- Hide unused rows
    for i = #detectedUpgrades + 1, #rowPool do
        if rowPool[i] then rowPool[i]:Hide() end
    end

    scrollChild:SetHeight(math.max(1, #detectedUpgrades * ROW_HEIGHT))
    radarFrame:Show()

    -- Play alert sound
    PlaySound(63971) -- Legendary loot toast
end

-- ============================================================
-- EVENT HANDLING
-- ============================================================
-- M+ flow: START → snapshot → SILENT during run → COMPLETED → compare
-- Non-M+ dungeons: CHAT_MSG_LOOT tracks loot in real-time (lightweight)

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("CHALLENGE_MODE_START")
eventFrame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
eventFrame:RegisterEvent("INSPECT_READY")

-- CHAT_MSG_LOOT is only registered when NOT in M+ (see below)
-- ZONE_CHANGED_NEW_AREA removed - no need to scan on zone changes

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        local db = GetDB()
        if db.windowPoint then
            local p = db.windowPoint
            radarFrame:ClearAllPoints()
            radarFrame:SetPoint(p[1], UIParent, p[3], p[4], p[5])
        end
        -- Check if we're in a dungeon on login/reload
        local _, instanceType = IsInInstance()
        inDungeon = (instanceType == "party")

    elseif event == "CHALLENGE_MODE_START" then
        -- M+ started: take snapshot, go silent until completion
        mythicPlusActive = true
        snapshotTaken = true
        inDungeon = true
        detectedUpgrades = {}
        lootedItems = {}
        -- Unregister loot tracking during M+ (no loot drops until end)
        eventFrame:UnregisterEvent("CHAT_MSG_LOOT")
        print("|cFF9482C9ADHDBiS LootRadar:|r M+ started - snapshot taken. Silent until completion.")
        C_Timer.After(2, SnapshotAllParty)

    elseif event == "CHALLENGE_MODE_COMPLETED" then
        -- M+ done: wait for chest loot, then compare
        print("|cFF9482C9ADHDBiS LootRadar:|r M+ completed! Scanning loot in 8 seconds...")
        C_Timer.After(8, function()
            if mythicPlusActive then
                ComparePartyGear()
                -- Re-enable loot tracking for after the run
                mythicPlusActive = false
                snapshotTaken = false
            end
        end)

    elseif event == "CHAT_MSG_LOOT" then
        -- Only fires in non-M+ dungeons (M0, heroic)
        local msg = ...
        if msg and inDungeon and not mythicPlusActive then
            OnLootMessage(msg)
        end

    elseif event == "INSPECT_READY" then
        local inspectGUID = ...
        if inspectCallback then
            for i = 1, 4 do
                local unit = "party" .. i
                if UnitExists(unit) and UnitGUID(unit) == inspectGUID then
                    local name = UnitName(unit)
                    if name then
                        if inspectCallback == "snapshot" then
                            partySnapshots[name] = SnapshotUnit(unit)
                        elseif inspectCallback == "compare" then
                            partySnapshots["_new_" .. name] = SnapshotUnit(unit)
                        end
                    end
                    ClearInspectPlayer()
                    break
                end
            end
            C_Timer.After(1.5, ProcessInspectQueue)
        end
    end
end)

-- ============================================================
-- SLASH COMMAND INTERFACE
-- ============================================================

ns.ToggleLootRadar = function(subCmd)
    if subCmd == "test" then
        -- Generate fake test data
        detectedUpgrades = {
            {
                looter = "TestPlayer",
                itemLink = GetInventoryItemLink("player", 1) or "|cff0070dd[Test Helm]|r",
                itemID = 0,
                ilvl = 639,
                reason = "bis",
                reasonText = "|cFFFFD100M+ BiS for " .. (GetPlayerSpec() or "your spec") .. "!|r",
                slotName = "Head",
            },
            {
                looter = "AnotherPlayer",
                itemLink = GetInventoryItemLink("player", 13) or "|cffa335ee[Test Trinket]|r",
                itemID = 0,
                ilvl = 642,
                reason = "ilvl",
                reasonText = "|cFF00FF00+13 ilvl upgrade|r (Trinket 1)",
                slotName = "Trinket 1",
            },
        }
        ShowLootRadarPanel()
        print("|cFF9482C9ADHDBiS LootRadar:|r Test data loaded.")

    elseif subCmd == "mode" then
        local db = GetDB()
        if db.messageMode == "whisper" then
            db.messageMode = "party"
        else
            db.messageMode = "whisper"
        end
        print("|cFF9482C9ADHDBiS LootRadar:|r Message mode: |cFFFFFF00" .. db.messageMode .. "|r")

    elseif subCmd == "clear" then
        detectedUpgrades = {}
        radarFrame:Hide()
        print("|cFF9482C9ADHDBiS LootRadar:|r Results cleared.")

    elseif subCmd == "help" then
        print("|cFF9482C9ADHDBiS LootRadar|r commands:")
        print("  |cFFFFFFFF/adhd radar|r - Toggle LootRadar panel")
        print("  |cFFFFFFFF/adhd radar mode|r - Toggle whisper/party chat mode")
        print("  |cFFFFFFFF/adhd radar test|r - Test with fake data")
        print("  |cFFFFFFFF/adhd radar clear|r - Clear results")
        print("  |cFFFFFFFF/adhd radar help|r - Show this help")

    else
        -- Toggle panel
        if radarFrame:IsShown() then
            radarFrame:Hide()
        else
            if #detectedUpgrades > 0 then
                ShowLootRadarPanel()
            else
                statusText:SetText("|cFF666666No upgrades detected yet.\nComplete a M+ dungeon to scan party loot.|r")
                statusText:Show()
                scrollFrame:Hide()
                radarFrame:SetHeight(100)
                radarFrame:Show()
            end
        end
    end
end
