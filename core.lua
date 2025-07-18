local rclc = LibStub("AceAddon-3.0"):GetAddon("RCLootCouncil")

local module = rclc:NewModule('RCLC Crests', 'AceComm-3.0', 'AceSerializer-3.0')

local coreVotingFrame = rclc:GetModule('RCVotingFrame')
local votingFrame = module:NewModule('RCLC Crests - Voting Frame', 'AceTimer-3.0', 'AceEvent-3.0')

local session = nil
local PLAYER_SLOT_CACHE = {}
function votingFrame:OnMessageReceived(msg, ...)
    if msg == "RCSessionChangedPre" then
        local s = unpack({...})
        session = s
        PLAYER_SLOT_CACHE = {}
    end
end

local function bagItems(frame, data, cols, row, realrow, column, fShow, table, ...)
end

local TRACKS = {
    -- Myth
    [978] = 684,
    -- Hero
    [974] = 671,
    -- Champ
    [973] = 658,
    -- Veteran
    -- TODO
}

local function isCurrentTrack(upgradeInfo)
    if not upgradeInfo then return false end
    return TRACKS[upgradeInfo.trackStringID] == upgradeInfo.maxItemLevel
end

-- bonus id for current season crafted items
local CURRENT_CRAFT_BONUS = 12040

local function isCurrentCrafted(itemLink)
    return string.find(itemLink, ':' .. CURRENT_CRAFT_BONUS .. ':') ~= nil
end

local function isCurrentTierToken(itemLink)
    -- TODO
    return false
end

local function iterBags()
    local currentBag = 0
    local maxBag = 4 -- ignoring reagent bag
    local currentSlot = 0
    local maxBagSlots = C_Container.GetContainerNumSlots(currentBag)
    return function()
        while true do
            currentSlot = currentSlot + 1
            if currentSlot > maxBagSlots then
                currentBag = currentBag + 1
                maxBagSlots = C_Container.GetContainerNumSlots(currentBag)
                currentSlot = 1
            end

            if currentBag > maxBag then
                return
            end

            local link = C_Container.GetContainerItemLink(currentBag, currentSlot)

            if link ~= nil then
                return link, currentBag, currentSlot
            end
        end
    end
end

local function listSlotItems(redundancySlotId)
    local result = {}

    for i = 1, 16 do
        local loc = ItemLocation:CreateFromEquipmentSlot(i)
        local equipped = C_Item.GetItemLink(loc)

        if equipped then
            local red = C_ItemUpgrade.GetHighWatermarkSlotForItem(equipped)
            if red == redundancySlotId then
                table.insert(result, equipped)
            end
        end
    end

    if equipped then
        table.insert(result, equipped)
    end

    for item, bag, slot in iterBags() do
        local upgradeInfo = C_Item.GetItemUpgradeInfo(item)
        local red = C_ItemUpgrade.GetHighWatermarkSlotForItem(item)
        if red == redundancySlotId then
            if isCurrentTrack(upgradeInfo) or isCurrentCrafted(item) or isCurrentTierToken(item) then
                table.insert(result, item)
            end
        end
    end
    return result
end

local function slotData(redundancySlotId)
    local items = listSlotItems(redundancySlotId)

    return {
        items = items,
        highWatermark = C_ItemUpgrade.GetHighWatermarkForSlot(redundancySlotId)
    }
end

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

local function trackUpgrade(self, frame, data, cols, row, realrow, column, fShow, table, ...)
    local loot = rclc:GetLootTable()

    if loot and session ~= nil and loot[session] then
        local player = data[realrow].name
        local item = loot[session].link
        local redundancySlotId = C_ItemUpgrade.GetHighWatermarkSlotForItem(item)
        local targetName = Ambiguate(player, 'mail')
        if PLAYER_SLOT_CACHE[targetName] and PLAYER_SLOT_CACHE[targetName][redundancySlotId] then
            local data = PLAYER_SLOT_CACHE[targetName][redundancySlotId]
            frame.text:SetText(data.highWatermark)
        else
            requestPlayerSlotData(targetName, redundancySlotId)
        end
    end
end

local MSG_FORMAT_VERSION = 1

function votingFrame:OnInitialize()
    -- parts of this are cribbed from the wowaudit plugin
    if not coreVotingFrame.scrollCols then -- RCVotingFrame hasn't been initialized.
        return self:ScheduleTimer("OnInitialize", 0.5)
    end

    table.insert(coreVotingFrame.scrollCols, 8, {
        name = 'Crest/Track Upgrade',
        DoCellUpdate = trackUpgrade,
        colName = 'crests-upgrade',
        width = 150,
    })
    table.insert(coreVotingFrame.scrollCols, 9, {
        name = 'Bags/Bank',
        DoCellUpdate = bagItems,
        colName = 'crests-bags-bank',
        width = 30,
    })
    
    self:RegisterMessage("RCSessionChangedPre", "OnMessageReceived")
    self:RegisterMessage('RCLCCrestUpdatePlayer', 'OnSlotDataReceived')
end

function module:OnCommReceived(message, distribution, sender)
    local data = module:Deserialize(message)
    DevTools_Dump(data)
    if data and data.version == MSG_FORMAT_VERSION then
    end
end

module:RegisterComm('RCLCCrests')

function module:RequestSlot(redundancySlotId, characterSlug)
    -- docs say that WHISPER only works on connected realms, with no mention of cross-realm groups. sticking to RAID
    module:SendCommMessage('RCLCCrests', self:Serialize({
        version = MSG_FORMAT_VERSION,
        type = 'request-slot',
        redundancySlotId = redundancySlotId,
        characterSlug = characterSlug
    }), 'RAID')
end

function votingFrame:OnSlotDataReceived(msg, targetName, redundancySlotId, data)
    if not PLAYER_SLOT_CACHE[targetName] then
        PLAYER_SLOT_CACHE[targetName] = {}
    end
    PLAYER_SLOT_CACHE[targetName][redundancySlotId] = data
end
