local rclc = LibStub("AceAddon-3.0"):GetAddon("RCLootCouncil")

local module = rclc:NewModule('RCLC Crests', 'AceComm-3.0', 'AceSerializer-3.0')

local coreVotingFrame = rclc:GetModule('RCVotingFrame')
local votingFrame = module:NewModule('RCLC Crests - Voting Frame', 'AceTimer-3.0', 'AceEvent-3.0')

---@class ItemData
---@field item string
---@field equipped? boolean|nil
---@field offspec? boolean|nil

---@class BagData
---@field items ItemData[]
---@field highWatermark number

---@type number|nil
local session = nil
---memory cache of player name -> slot id -> bag data
---@type table<string, table<number, BagData>>
local PLAYER_SLOT_CACHE = {}

function votingFrame:OnMessageReceived(msg, ...)
    if msg == "RCSessionChangedPre" then
        local s = unpack({ ... })
        session = s
        PLAYER_SLOT_CACHE = {}
    end
end

---get the track label and track id from a tier token bonus id. nil, nil if the item does not have any known bonus id
---@param item string
---@return string|nil
---@return integer|nil
local function trackFromTokenBonusId(item)
    if string.find(item, ':10355:') then
        return 'Hero', 974
    elseif string.find(item, ':10356:') then
        return 'Myth', 978
    elseif string.find(item, ':10354:') then
        return 'Champion', 973
    elseif string.find(item, ':10353:') then
        return 'Veteran', 972
    end

    return nil, nil
end

local TRACKS = {
    -- Myth
    [978] = 684,
    -- Hero
    [974] = 671,
    -- Champ
    [973] = 658,
    -- Veteran
    [972] = 645,
}

local TRACK_DISPLAY_QUALITY = {
    [978] = 4,
    [974] = 3,
    [973] = 2,
    [972] = 1,
}

local function formatTrackName(trackId, trackName)
    local quality = TRACK_DISPLAY_QUALITY[trackId] or 0

    return '|cnIQ' .. quality .. ':' .. trackName .. '|r'
end

---check if the upgrade info represents a current-tier track. the track ids remain the same across seasons, but the ilvls do not
---@param upgradeInfo unknown|nil
---@return boolean
local function isCurrentTrack(upgradeInfo)
    if not upgradeInfo then return false end
    return TRACKS[upgradeInfo.trackStringID] == upgradeInfo.maxItemLevel
end

-- bonus id for current season crafted items
local CURRENT_CRAFT_BONUS = 12040

---check if the item link represents a current-tier spark craft
---@param itemLink string
---@return boolean
local function isCurrentCrafted(itemLink)
    return string.find(itemLink, ':' .. CURRENT_CRAFT_BONUS .. ':') ~= nil
end

local TOKEN_SLOT_TO_REDUNDANCY_ID = {
    ChestSlot = Enum.ItemRedundancySlot.Chest,
    HandsSlot = Enum.ItemRedundancySlot.Hand,
    HeadSlot = Enum.ItemRedundancySlot.Head,
    LegsSlot = Enum.ItemRedundancySlot.Legs,
    ShoulderSlot = Enum.ItemRedundancySlot.Shoulder,
}

-- mostly copied from RCLC, with the addition of the omni token
local CURRENT_TIER_TOKENS = {
    [228799] = "ChestSlot",    -- Dreadful Greased Gallybux,
    [228800] = "ChestSlot",    -- Mystic Greased Gallybux,
    [228801] = "ChestSlot",    -- Venerated Greased Gallybux,
    [228802] = "ChestSlot",    -- Zenith Greased Gallybux,
    [228803] = "HandsSlot",    -- Dreadful Bloody Gallybux,
    [228804] = "HandsSlot",    -- Mystic Bloody Gallybux,
    [228805] = "HandsSlot",    -- Venerated Bloody Gallybux,
    [228806] = "HandsSlot",    -- Zenith Bloody Gallybux,
    [228807] = "HeadSlot",     -- Dreadful Gilded Gallybux,
    [228808] = "HeadSlot",     -- Mystic Gilded Gallybux,
    [228809] = "HeadSlot",     -- Venerated Gilded Gallybux,
    [228810] = "HeadSlot",     -- Zenith Gilded Gallybux,
    [228811] = "LegsSlot",     -- Dreadful Rusty Gallybux,
    [228812] = "LegsSlot",     -- Mystic Rusty Gallybux,
    [228813] = "LegsSlot",     -- Venerated Rusty Gallybux,
    [228814] = "LegsSlot",     -- Zenith Rusty Gallybux,
    [228815] = "ShoulderSlot", -- Dreadful Polished Gallybux,
    [228816] = "ShoulderSlot", -- Mystic Polished Gallybux,
    [228817] = "ShoulderSlot", -- Venerated Polished Gallybux,
    [228818] = "ShoulderSlot", -- Zenith Polished Gallybux,

    [228819] = "MultiSlots"
}

---get the redundancy slot id(s) for the item. this may return multiple (e.g. for omnitokens)
---@param itemLink string
---@return number[]
local function tierTokenRedundancySlots(itemLink)
    local id = C_Item.GetItemIDForItemInfo(itemLink)
    local slot = CURRENT_TIER_TOKENS[id] or RCTokenTable[id] or rclc:GetTokenSlotFromTooltip(id)

    if slot == "MultiSlots" then
        return TOKEN_SLOT_TO_REDUNDANCY_ID
    elseif slot ~= "" and slot ~= nil then
        return { TOKEN_SLOT_TO_REDUNDANCY_ID[slot] }
    end

    return {}
end

---check if the item link is a current-tier token
---@param itemLink string
---@return boolean
local function isCurrentTierToken(itemLink)
    return CURRENT_TIER_TOKENS[C_Item.GetItemIDForItemInfo(itemLink)] ~= nil
end

---iterator over bag contents
local function iterBags()
    local currentBag = 0
    local maxBag = 4 -- ignoring reagent bag
    local currentSlot = 0
    local maxBagSlots = C_Container.GetContainerNumSlots(currentBag)
    ---@return string|nil, number|nil, number|nil
    return function()
        while true do
            currentSlot = currentSlot + 1
            if currentSlot > maxBagSlots then
                currentBag = currentBag + 1
                maxBagSlots = C_Container.GetContainerNumSlots(currentBag)
                currentSlot = 1
            end

            if currentBag > maxBag then
                return nil
            end

            local link = C_Container.GetContainerItemLink(currentBag, currentSlot)

            if link ~= nil then
                return link, currentBag, currentSlot
            end
        end
    end
end

local function matchesRedundancySlot_(left, right)
    if left == right then
        return true
    elseif left == Enum.ItemRedundancySlot.Twohand then
        return (
            right == Enum.ItemRedundancySlot.OnehandWeapon or
            right == Enum.ItemRedundancySlot.OnehandWeaponSecond or
            right == Enum.ItemRedundancySlot.MainhandWeapon or
            right == Enum.ItemRedundancySlot.Offhand
        )
    elseif (left == Enum.ItemRedundancySlot.OnehandWeapon or left == Enum.ItemRedundancySlot.OnehandWeaponSecond) then
        return
            right == Enum.ItemRedundancySlot.OnehandWeapon or
            right == Enum.ItemRedundancySlot.OnehandWeaponSecond or
            right == Enum.ItemRedundancySlot.Offhand or
            right == Enum.ItemRedundancySlot.MainhandWeapon
    else
        return (right == Enum.ItemRedundancySlot.OnehandWeapon and left == Enum.ItemRedundancySlot.MainhandWeapon) or
            (right == Enum.ItemRedundancySlot.OnehandWeapon and left == Enum.ItemRedundancySlot.Offhand)
    end
end

---check if two redundancy slots match. this handles the relationship between onehand / mainhand / offhand / twohand weapons (i hope)
---@param left number
---@param right number
---@return boolean
local function matchesRedundancySlot(left, right)
    return matchesRedundancySlot_(left, right) or matchesRedundancySlot_(right, left)
end

---check if the item is usable by the current player class. some items do not have tags for this, and we assume they are usable
---@param item string
---@return boolean
local function isUsableByClass(item)
    local info = C_Item.GetItemSpecInfo(item)

    return info == nil or #info > 0
end

---check if the item is intended for the current player spec. some items do not have tags for this, and we assume they are. "intended" means things like dps trinkets aren't flagged for tank specs. this is informative because fuck tank trinkets
---@param item string
---@return boolean
local function isIntendedForCurrentSpec(item)
    local info = C_Item.GetItemSpecInfo(item)

    if info == nil then
        return true -- default assume yes
    end

    local currentSpecId = GetSpecializationInfo(GetSpecialization())
    for _, specId in ipairs(info) do
        if specId == currentSpecId then
            return true
        end
    end

    return false
end

-- TODO: should redo this to do one scan and one message to the channel, though i suppose could also argue that any autopassers shouldn't get requested
---@param redundancySlotId number
---@return ItemData[]
local function listSlotItems(redundancySlotId)
    ---@type ItemData[]
    local result = {}

    for i = 1, 16 do
        local loc = ItemLocation:CreateFromEquipmentSlot(i)
        if C_Item.DoesItemExist(loc) then
            local equipped = C_Item.GetItemLink(loc)

            if equipped then
                local red = C_ItemUpgrade.GetHighWatermarkSlotForItem(equipped)
                if matchesRedundancySlot(red, redundancySlotId) then
                    table.insert(result, { item = equipped, equipped = true })
                end
            end
        end
    end

    for item, bag, slot in iterBags() do
        local upgradeInfo = C_Item.GetItemUpgradeInfo(item)
        local red = C_ItemUpgrade.GetHighWatermarkSlotForItem(item)
        if red == -1 then
            local slots = tierTokenRedundancySlots(item)
            for _, slot in pairs(slots) do
                if matchesRedundancySlot(slot, redundancySlotId) then
                    red = slot
                    break
                end
            end
        end
        if matchesRedundancySlot(red, redundancySlotId) and isUsableByClass(item) then
            if isCurrentTrack(upgradeInfo) or isCurrentCrafted(item) or isCurrentTierToken(item) then
                table.insert(result, {
                    item = item,
                    offspec = not isIntendedForCurrentSpec(item)
                })
            end
        end
    end
    return result
end

---collect slot data from the current player
---@param redundancySlotId number
---@return BagData
local function slotData(redundancySlotId)
    local items = listSlotItems(redundancySlotId)

    return {
        items = items,
        highWatermark = C_ItemUpgrade.GetHighWatermarkForSlot(redundancySlotId)
    }
end

---@param player string
---@param redundancySlotId number
local function requestPlayerSlotData(player, redundancySlotId)
    local targetName = Ambiguate(player, 'mail')
    if PLAYER_SLOT_CACHE[targetName] and PLAYER_SLOT_CACHE[targetName][redundancySlotId] then
        return -- already have the data
    end

    local name, server = UnitFullName('player')
    if name .. '-' .. server == targetName then
        votingFrame:SendMessage('RCLCCrestUpdatePlayer', targetName, redundancySlotId, slotData(redundancySlotId))
        return -- do nothing for self
    end

    module:RequestSlot(redundancySlotId, targetName)
end

local tipFrame = CreateFrame('GameTooltip', 'RCLCCrestsTooltip', nil, 'SharedTooltipTemplate')
tipFrame:ClearLines()

local FONT = [[Interface\addons\RCLC Crests\resources\fonts\FiraMono-Regular.otf]]
for i = 1, 2 do
    _G['RCLCCrestsTooltipTextLeft' .. i]:SetFont('fonts/frizqt__.ttf', 10)
    _G['RCLCCrestsTooltipTextRight' .. i]:SetFont(FONT, 10)
end
for i = 1, 50 do
    local left = tipFrame:CreateFontString()
    left:SetFont('fonts/frizqt__.ttf', 10)
    local right = tipFrame:CreateFontString()
    right:SetFont(FONT, 10)
    tipFrame:AddFontStrings(left, right)
end

local function Tooltip_Line(text)
    tipFrame:AddDoubleLine(text, '')
end

local function Tooltip_LabelledLine(leftText, rightText)
    tipFrame:AddDoubleLine(leftText, rightText)
end

---determine the highest track from *main-spec* items in the list
---@param items ItemData[]
---@return string|nil
---@return integer|nil
local function highestTrackFromItems(items)
    local track = nil
    local trackIlvl = nil
    for _, itemData in pairs(items) do
        if not itemData.offspec then
            local item = itemData.item
            local upgradeInfo = C_Item.GetItemUpgradeInfo(item)
            if upgradeInfo and (not trackIlvl or upgradeInfo.maxItemLevel > trackIlvl) then
                track = upgradeInfo.trackString
                trackIlvl = upgradeInfo.maxItemLevel
            elseif isCurrentTierToken(item) then
                local trackName, trackId = trackFromTokenBonusId(item)

                if TRACKS[trackId] and (not trackIlvl or TRACKS[trackId] > trackIlvl) then
                    track = trackName
                    trackIlvl = TRACKS[trackId]
                end
            end
        end
    end

    return track, trackIlvl
end

---comparator for sorting item data. sort is: equipped desc, offspec asc, max ilvl desc, current ilvl desc
---@param a ItemData
---@param b ItemData
---@return boolean
local function compareItemData(a, b)
    if b.equipped and not a.equipped then
        return false
    end
    if a.equipped and not b.equipped then
        return true
    end

    if b.offspec and not a.offspec then
        return true --note: flipped
    end
    if a.offspec and not b.offspec then
        return false
    end

    local up_a = C_Item.GetItemUpgradeInfo(a.item)
    local up_b = C_Item.GetItemUpgradeInfo(b.item)

    if up_b and up_a then
        if up_b.maxItemLevel ~= up_a.maxItemLevel then
            return up_b.maxItemLevel < up_a.maxItemLevel
        end
    end

    local ilvl_a = C_Item.GetDetailedItemLevelInfo(a.item)
    local ilvl_b = C_Item.GetDetailedItemLevelInfo(b.item)

    if ilvl_a and ilvl_b then
        return ilvl_b < ilvl_a
    end

    return ilvl_a ~= nil
end

local function trackUpgrade(self, frame, data, cols, row, realrow, column, fShow, ...)
    local loot = rclc:GetLootTable()

    if loot and session ~= nil and loot[session] then
        local player = data[realrow].name
        local item = loot[session].link
        local redundancySlotId = C_ItemUpgrade.GetHighWatermarkSlotForItem(item)
        local slots
        if redundancySlotId == -1 then
            slots = tierTokenRedundancySlots(item)
        else
            slots = { redundancySlotId }
        end

        local targetName = Ambiguate(player, 'mail')
        local slotData = {}
        local tooltipEnabled = false

        local track, trackIlvl, watermarkIlvl, waiting = nil, nil, nil, false
        for _, redundancySlotId in pairs(slots) do
            if PLAYER_SLOT_CACHE[targetName] and PLAYER_SLOT_CACHE[targetName][redundancySlotId] then
                local data = PLAYER_SLOT_CACHE[targetName][redundancySlotId]
                slotData[redundancySlotId] = data
                local track_, trackIlvl_ = highestTrackFromItems(data.items)
                -- handle multi slot items by taking the worst highest upgrade level
                if trackIlvl_ and (not trackIlvl or trackIlvl_ < trackIlvl) then
                    trackIlvl = trackIlvl
                    track = track_
                end
                if data.highWatermark and (not watermarkIlvl or watermarkIlvl > data.highWatermark) then
                    watermarkIlvl = data.highWatermark
                end
                tooltipEnabled = true
            else
                frame.text:SetText('Waiting...')
                requestPlayerSlotData(targetName, redundancySlotId)
                waiting = true
            end
        end

        if not waiting and watermarkIlvl then
            local label = string.format('%s (|Tinterface/icons/inv_valorstone_base:0:0:2:0|t to %d)', track or 'None',
                watermarkIlvl)
            frame.text:SetText(label)
        end

        if tooltipEnabled then
            frame:SetScript('OnEnter', function()
                tipFrame:SetOwner(frame, 'ANCHOR_BOTTOM')
                tipFrame:ClearLines()
                Tooltip_Line(targetName)
                for slotId, data in pairs(slotData) do
                    if #data.items > 0 then
                        local slot = select(9, C_Item.GetItemInfo(data.items[1].item))
                        Tooltip_LabelledLine(_G[slot],
                            string.format('|Tinterface/icons/inv_valorstone_base:0:0:2:0|t to %d', data.highWatermark))

                        Tooltip_LabelledLine('Bag Item',
                            string.format('%8s | %4s | %4s | %5s | %5s', 'Track', 'ilvl', 'max', 'stats', 'tert'))
                        tipFrame:AddLine()

                        table.sort(data.items, compareItemData)

                        for _, itemData in pairs(data.items) do
                            local item = itemData.item
                            local upgrade = C_Item.GetItemUpgradeInfo(item)
                            local ilvl = C_Item.GetDetailedItemLevelInfo(item)
                            local stats = C_Item.GetItemStats(item)

                            local statText = ''
                            local secondaryMax = nil
                            local tertText = '-'
                            for stat, amount in pairs(stats) do
                                if stat == 'ITEM_MOD_CR_AVOIDANCE_SHORT' or stat == 'ITEM_MOD_CR_LIFESTEAL_SHORT' or stat == 'ITEM_MOD_CR_SPEED_SHORT' then
                                    tertText = string.sub(_G[stat], 1, 5)
                                elseif stat == 'ITEM_MOD_HASTE_RATING_SHORT' or stat == 'ITEM_MOD_CRIT_RATING_SHORT' or stat == 'ITEM_MOD_VERSATILITY' or stat == 'ITEM_MOD_MASTERY_RATING_SHORT' then
                                    if secondaryMax == nil then
                                        secondaryMax = amount
                                        statText = string.sub(_G[stat], 1, 1)
                                    else
                                        if amount > secondaryMax then
                                            secondaryMax = amount
                                            statText = string.sub(_G[stat], 1, 1) .. '/' .. statText
                                        else
                                            statText = statText .. '/' .. string.sub(_G[stat], 1, 1)
                                        end
                                    end
                                end
                            end

                            local trackName, trackIlvl = '', '-'
                            if isCurrentTierToken(item) then
                                local trackName_, trackId = trackFromTokenBonusId(item)

                                if TRACKS[trackId] then
                                    trackName = formatTrackName(trackId, trackName_)
                                    trackIlvl = TRACKS[trackId]
                                end
                            elseif upgrade and upgrade.trackString then
                                trackName = formatTrackName(upgrade.trackStringID, upgrade.trackString)
                                trackIlvl = upgrade.maxItemLevel
                            end

                            local leftText = item

                            if itemData.equipped then
                                leftText = leftText .. ' (Eq)'
                            end

                            if itemData.offspec then
                                leftText = leftText .. ' (OS)'
                            end

                            Tooltip_LabelledLine(
                                leftText,
                                string.format('%8s | %4s | %4s | %5s | %5s',
                                    trackName,
                                    ilvl,
                                    trackIlvl,
                                    statText,
                                    tertText))
                        end
                        Tooltip_Line(' ')
                    end
                end

                tipFrame:Show()
            end)
            frame:SetScript('OnLeave', function()
                tipFrame:Hide()
            end)
        end
    end
end

local MSG_FORMAT_VERSION = 2

function votingFrame:OnInitialize()
    -- parts of this are cribbed from the wowaudit plugin
    if not coreVotingFrame.scrollCols then -- RCVotingFrame hasn't been initialized.
        return self:ScheduleTimer("OnInitialize", 0.5)
    end

    table.insert(coreVotingFrame.scrollCols, 8, {
        name = 'Highest Upgrade Track',
        DoCellUpdate = trackUpgrade,
        colName = 'crests-upgrade',
        width = 150,
    })

    self:RegisterMessage("RCSessionChangedPre", "OnMessageReceived")
    self:RegisterMessage('RCLCCrestUpdatePlayer', 'OnSlotDataReceived')
end

local REQUEST_SEMAPHORE = {}

function module:OnCommReceived(prefix, message, distribution, sender)
    local success, data = module:Deserialize(message)
    if success and data and data.version == MSG_FORMAT_VERSION then
        if data.type == 'request-slot' then
            REQUEST_SEMAPHORE[message] = (REQUEST_SEMAPHORE[message] or 0) + 1

            C_Timer.After(0.1, function()
                REQUEST_SEMAPHORE[message] = REQUEST_SEMAPHORE[message] - 1
                if REQUEST_SEMAPHORE[message] > 0 then
                    return -- another request came in. respond later
                end

                local reply = {
                    redundancySlotId = data.redundancySlotId,
                    slotData = slotData(data.redundancySlotId),
                    version = MSG_FORMAT_VERSION,
                    player = string.join("-", UnitFullName('player')),
                    type = 'request-slot-reply'
                }

                module:SendCommMessage('RCLCCrests', self:Serialize(reply), 'RAID')
            end)
        elseif data.type == 'request-slot-reply' then
            votingFrame:SendMessage('RCLCCrestUpdatePlayer', data.player, data.redundancySlotId, data.slotData)
        end
    end
end

module:RegisterComm('RCLCCrests')

local PENDING_REQUESTS = {}

function module:RequestSlot(redundancySlotId, characterSlug)
    local msg = self:Serialize({
        version = MSG_FORMAT_VERSION,
        type = 'request-slot',
        redundancySlotId = redundancySlotId,
        characterSlug = characterSlug
    })

    if PENDING_REQUESTS[msg] and time() - PENDING_REQUESTS[msg] < 3 then
        return -- don't request more often than once per 3s
    end

    -- docs say that WHISPER only works on connected realms, with no mention of cross-realm groups. sticking to RAID
    module:SendCommMessage('RCLCCrests', msg, 'RAID')
    PENDING_REQUESTS[msg] = time()
end

function votingFrame:OnSlotDataReceived(msg, targetName, redundancySlotId, data)
    if not PLAYER_SLOT_CACHE[targetName] then
        PLAYER_SLOT_CACHE[targetName] = {}
    end
    PLAYER_SLOT_CACHE[targetName][redundancySlotId] = data
    coreVotingFrame:Update()
end
