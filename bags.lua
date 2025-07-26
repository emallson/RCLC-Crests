---@class RCLCCrestsPrivate
local private = select(2, ...)

---iterator over bag contents
function private.iterBags()
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