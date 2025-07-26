---@class RCLCCrestsPrivate
local private = select(2, ...)

---collect slot data from the current player
---@param redundancySlotId number
---@return BagData
local function slotData(redundancySlotId)
    local items = private.listSlotItems(redundancySlotId)

    return {
        items = items,
        highWatermark = C_ItemUpgrade.GetHighWatermarkForSlot(redundancySlotId)
    }
end

---memory cache of player name -> slot id -> bag data
---@type table<string, table<number, BagData>>
local PLAYER_SLOT_CACHE = {}

function private.resetSlotCache()
    PLAYER_SLOT_CACHE = {}
end

function private.getCachedSlotData(name, redundancySlotId)
    local targetName = Ambiguate(name, 'mail')
    if PLAYER_SLOT_CACHE[targetName] and PLAYER_SLOT_CACHE[targetName][redundancySlotId] then
        return PLAYER_SLOT_CACHE[targetName][redundancySlotId]
    end

    return nil
end

local PENDING_REQUESTS = {}

local MSG_FORMAT_VERSION = 2

local function RequestSlot(redundancySlotId, characterSlug)
    local msg = private.module:Serialize({
        version = MSG_FORMAT_VERSION,
        type = 'request-slot',
        redundancySlotId = redundancySlotId,
        characterSlug = characterSlug
    })

    if PENDING_REQUESTS[msg] and time() - PENDING_REQUESTS[msg] < 3 then
        return -- don't request more often than once per 3s
    end

    -- always using addon comms to help simplify testing
    if IsInGroup(LE_PARTY_CATEGORY_HOME) then
        private.module:SendCommMessage('RCLCCrests', msg, 'RAID')
    else
        private.module:SendCommMessage('RCLCCrests', msg, 'WHISPER', string.join('-', UnitFullName('player')))
    end
    PENDING_REQUESTS[msg] = time()
end


---@param player string
---@param redundancySlotId number
function private.requestPlayerSlotData(player, redundancySlotId)
    local targetName = Ambiguate(player, 'mail')
    if PLAYER_SLOT_CACHE[targetName] and PLAYER_SLOT_CACHE[targetName][redundancySlotId] then
        return -- already have the data
    end

    RequestSlot(redundancySlotId, targetName)
end

local REQUEST_SEMAPHORE = {}

function private.module:OnCommReceived(prefix, message, distribution, sender)
    local success, data = self:Deserialize(message)
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

                self:SendCommMessage('RCLCCrests', self:Serialize(reply), distribution, sender)
            end)
        elseif data.type == 'request-slot-reply' then
            if not PLAYER_SLOT_CACHE[data.player] then
                PLAYER_SLOT_CACHE[data.player] = {}
            end
            PLAYER_SLOT_CACHE[data.player][data.redundancySlotId] = data.slotData
            private.votingFrame:SendMessage('RCLCCrestUpdatePlayer')
        end
    end
end

private.module:RegisterComm('RCLCCrests')
