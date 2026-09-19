local addonName, ns = ...

local BAG_ICON = "Interface\\Icons\\INV_Misc_Bag_08"

ns.AddDefaults({
    bags = {
        showTotal = true,
    },
})

--- Free bag slots, as a bag icon followed by the count, and optionally the
-- total after it. Pure, so it is unit tested directly.
local function formatBagSpace(free, iconSize, total)
    free = math.max(0, math.floor(tonumber(free) or 0))
    iconSize = math.max(1, math.floor(tonumber(iconSize) or 12))

    local count = tostring(free)
    if total then
        count = string.format("%d/%d", free, math.max(0, math.floor(total)))
    end

    return string.format("|T%s:%d:%d:0:0|t %s", BAG_ICON, iconSize, iconSize, count)
end

ns.FormatBagSpace = formatBagSpace

--- Free slots across the backpack and every general purpose bag.
-- Bags with a type of their own -- quivers, herb bags, enchanting bags -- are
-- left out: their free slots take only particular items, so counting them
-- would promise room that is not there for anything you are likely to loot.
local function freeBagSlots()
    local get = (C_Container and C_Container.GetContainerNumFreeSlots)
        or GetContainerNumFreeSlots
    if not get then
        return 0
    end

    local free = 0
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        local slots, kind = get(bag)
        if slots and (not kind or kind == 0) then
            free = free + slots
        end
    end

    return free
end

ns.FreeBagSlots = freeBagSlots

--- Total slots across the same bags the free count comes from.
local function totalBagSlots()
    local get = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
    local kindOf = (C_Container and C_Container.GetContainerNumFreeSlots)
        or GetContainerNumFreeSlots
    if not get or not kindOf then
        return 0
    end

    local total = 0
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        -- Call it outright. Written as `kindOf and kindOf(bag)` the `and`
        -- yields a single value, the bag type is silently dropped, and every
        -- bag counts as general purpose.
        local _, kind = kindOf(bag)
        if not kind or kind == 0 then
            total = total + (get(bag) or 0)
        end
    end

    return total
end

ns.TotalBagSlots = totalBagSlots

ns.RegisterSetting({
    store = "bags",
    key = "showTotal",
    type = "checkbox",
    -- Under the module's own switch, since it only means anything when the
    -- block is on the bar at all.
    parent = "modules.bags",
    name = "Show total bag slots",
    tooltip = "Reads 12/40 rather than 12.",
    onChange = function()
        local module = ns.Bar:GetModule("bags")
        if module then
            module:Refresh()
        end
    end,
})

ns.Bar:RegisterModule({
    name = "bags",
    label = "bag space",
    side = "LEFT",
    order = 20,
    -- BAG_UPDATE fires once per bag per change; the delayed one fires once
    -- after the batch, which is what the bar wants.
    events = { "BAG_UPDATE_DELAYED", "PLAYER_ENTERING_WORLD" },

    OnCreate = function(module)
        module.text = module.frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        module.text:SetPoint("LEFT")
    end,

    OnUpdate = function(module)
        local _, fontSize = module.text:GetFont()
        local total = ns.db.bags.showTotal and totalBagSlots() or nil
        module.text:SetText(formatBagSpace(freeBagSlots(), fontSize, total))
        module:SetWidth(module.text:GetStringWidth())
    end,

    OnClick = function(_, button)
        if button ~= "LeftButton" then
            return
        end

        local open = OpenAllBags or ToggleAllBags
        if open then
            open()
        end
    end,
})
