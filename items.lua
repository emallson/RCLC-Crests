---@class RCLCCrestsPrivate
local private = select(2, ...)

local rclc = LibStub("AceAddon-3.0"):GetAddon("RCLootCouncil")

---get the track label and track id from a tier token bonus id. nil, nil if the item does not have any known bonus id
---@param item string
---@return string|nil
---@return integer|nil
function private.trackFromTokenBonusId(item)
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

private.TRACKS = {
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

function private.formatTrackName(trackId, trackName)
    local quality = TRACK_DISPLAY_QUALITY[trackId] or 0

    return '|cnIQ' .. quality .. ':' .. trackName .. '|r'
end


---check if the upgrade info represents a current-tier track. the track ids remain the same across seasons, but the ilvls do not
---@param upgradeInfo unknown|nil
---@return boolean
local function isCurrentTrack(upgradeInfo)
    if not upgradeInfo then return false end
    return private.TRACKS[upgradeInfo.trackStringID] == upgradeInfo.maxItemLevel
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
function private.tierTokenRedundancySlots(itemLink)
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
function private.isCurrentTierToken(itemLink)
    return CURRENT_TIER_TOKENS[C_Item.GetItemIDForItemInfo(itemLink)] ~= nil
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
function private.listSlotItems(redundancySlotId)
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

    for item, bag, slot in private.iterBags() do
        local upgradeInfo = C_Item.GetItemUpgradeInfo(item)
        local red = C_ItemUpgrade.GetHighWatermarkSlotForItem(item)
        if red == -1 then
            local slots = private.tierTokenRedundancySlots(item)
            for _, slot in pairs(slots) do
                if matchesRedundancySlot(slot, redundancySlotId) then
                    red = slot
                    break
                end
            end
        end
        if matchesRedundancySlot(red, redundancySlotId) and isUsableByClass(item) then
            if isCurrentTrack(upgradeInfo) or isCurrentCrafted(item) or private.isCurrentTierToken(item) then
                table.insert(result, {
                    item = item,
                    offspec = not isIntendedForCurrentSpec(item)
                })
            end
        end
    end
    return result
end

---determine the highest track from *main-spec* items in the list
---@param items ItemData[]
---@return string|nil
---@return integer|nil
function private.highestTrackFromItems(items)
    local track = nil
    local trackIlvl = nil
    for _, itemData in pairs(items) do
        if not itemData.offspec then
            local item = itemData.item
            local upgradeInfo = C_Item.GetItemUpgradeInfo(item)
            if upgradeInfo and (not trackIlvl or upgradeInfo.maxItemLevel > trackIlvl) then
                track = upgradeInfo.trackString
                trackIlvl = upgradeInfo.maxItemLevel
            elseif private.isCurrentTierToken(item) then
                local trackName, trackId = private.trackFromTokenBonusId(item)

                if private.TRACKS[trackId] and (not trackIlvl or private.TRACKS[trackId] > trackIlvl) then
                    track = trackName
                    trackIlvl = private.TRACKS[trackId]
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
function private.compareItemData(a, b)
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