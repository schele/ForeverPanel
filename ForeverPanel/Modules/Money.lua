local addonName, ns = ...

local GOLD_ICON = "Interface\\MoneyFrame\\UI-GoldIcon"
local SILVER_ICON = "Interface\\MoneyFrame\\UI-SilverIcon"
local COPPER_ICON = "Interface\\MoneyFrame\\UI-CopperIcon"

local function coinIcon(path, size)
    return string.format("|T%s:%d:%d:2:0|t", path, size, size)
end

--- Build the money string with the in-game coin icons.
-- Deliberately different from GetCoinTextureString, which hides denominations
-- that are zero: all three are always shown, so the block reads the same way
-- whatever you are carrying. Amounts are not padded, so the block does change
-- width as silver and copper cross ten; the bar re-flows to suit.
local function formatMoney(copper, iconSize)
    copper = math.max(0, math.floor(tonumber(copper) or 0))
    iconSize = math.max(1, math.floor(tonumber(iconSize) or 12))

    local goldAmount = math.floor(copper / 10000)
    local silverAmount = math.floor((copper % 10000) / 100)
    local copperAmount = copper % 100

    local goldText = BreakUpLargeNumbers and BreakUpLargeNumbers(goldAmount) or tostring(goldAmount)

    return string.format(
        "%s%s %d%s %d%s",
        goldText,
        coinIcon(GOLD_ICON, iconSize),
        silverAmount,
        coinIcon(SILVER_ICON, iconSize),
        copperAmount,
        coinIcon(COPPER_ICON, iconSize)
    )
end

ns.FormatMoney = formatMoney

ns.Bar:RegisterModule({
    name = "money",
    side = "LEFT",
    order = 10,
    events = { "PLAYER_MONEY", "PLAYER_ENTERING_WORLD" },

    OnCreate = function(module)
        module.text = module.frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        module.text:SetPoint("LEFT")
    end,

    OnUpdate = function(module)
        local _, fontSize = module.text:GetFont()
        module.text:SetText(formatMoney(GetMoney(), fontSize))
        module:SetWidth(module.text:GetStringWidth())
    end,
})
