---@class RCLCCrestsPrivate
local private = select(2, ...)

local rclc = LibStub("AceAddon-3.0"):GetAddon("RCLootCouncil")
private.module = rclc:NewModule('RCLC Crests', 'AceComm-3.0', 'AceSerializer-3.0')

local coreVotingFrame = rclc:GetModule('RCVotingFrame')
local votingFrame = private.module:NewModule('RCLC Crests - Voting Frame', 'AceTimer-3.0', 'AceEvent-3.0')
private.votingFrame = votingFrame

---@class ItemData
---@field item string
---@field equipped? boolean|nil
---@field offspec? boolean|nil

---@class BagData
---@field items ItemData[]
---@field highWatermark number

---@type number|nil
local session = nil

function votingFrame:OnMessageReceived(msg, ...)
    if msg == "RCSessionChangedPre" then
        local s = unpack({ ... })
        session = s
        private.resetSlotCache()
    end
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

local function trackUpgrade(self, frame, data, cols, row, realrow, column, fShow, ...)
    local loot = rclc:GetLootTable()

    if loot and session ~= nil and loot[session] then
        local player = data[realrow].name
        local item = loot[session].link
        local redundancySlotId = C_ItemUpgrade.GetHighWatermarkSlotForItem(item)
        local slots
        if redundancySlotId == -1 then
            slots = private.tierTokenRedundancySlots(item)
        else
            slots = { redundancySlotId }
        end

        local targetName = Ambiguate(player, 'mail')
        local slotData = {}
        local tooltipEnabled = false

        local track, trackIlvl, watermarkIlvl, waiting = nil, nil, nil, false
        for _, redundancySlotId in pairs(slots) do
            local data = private.getCachedSlotData(targetName, redundancySlotId)
            if data then
                slotData[redundancySlotId] = data
                local track_, trackIlvl_ = private.highestTrackFromItems(data.items)
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
                private.requestPlayerSlotData(targetName, redundancySlotId)
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

                        table.sort(data.items, private.compareItemData)

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
                            if private.isCurrentTierToken(item) then
                                local trackName_, trackId = private.trackFromTokenBonusId(item)

                                if private.TRACKS[trackId] then
                                    trackName = private.formatTrackName(trackId, trackName_)
                                    trackIlvl = private.TRACKS[trackId]
                                end
                            elseif upgrade and upgrade.trackString then
                                trackName = private.formatTrackName(upgrade.trackStringID, upgrade.trackString)
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

function votingFrame:OnSlotDataReceived(msg)
    coreVotingFrame:Update()
end
