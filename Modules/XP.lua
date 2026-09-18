local addonName, ns = ...

--- Percentage of the current level still to go, as "xx.xx% left".
-- Returns nil when there is no XP bar to describe (max level, or XP turned
-- off), which tells the module to hide itself.
local function formatXPRemaining(xp, xpMax)
    xp = tonumber(xp) or 0
    xpMax = tonumber(xpMax) or 0

    if xpMax <= 0 then
        return nil
    end

    local remaining = math.max(0, xpMax - xp)
    return string.format("%.2f%% left", remaining / xpMax * 100)
end

ns.FormatXPRemaining = formatXPRemaining

ns.Bar:RegisterModule({
    name = "xp",
    side = "LEFT",
    order = 10,
    events = {
        "PLAYER_XP_UPDATE",
        "PLAYER_LEVEL_UP",
        "PLAYER_ENTERING_WORLD",
        "ENABLE_XP_GAIN",
        "DISABLE_XP_GAIN",
    },

    OnCreate = function(module)
        module.text = module.frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        module.text:SetPoint("LEFT")
    end,

    OnUpdate = function(module)
        local disabled = IsXPUserDisabled and IsXPUserDisabled()
        local text = not disabled and formatXPRemaining(UnitXP("player"), UnitXPMax("player")) or nil

        if not text then
            module:SetShown(false)
            return
        end

        module.text:SetText(text)
        module:SetWidth(module.text:GetStringWidth())
        module:SetShown(true)
    end,
})
