local addonName, ns = ...

ns.AddDefaults({
    xp = {
        -- Counting up is the default: "how far am I" reads more naturally than
        -- "how far is left" for most people.
        countDown = false,
    },
})

-- Deliberately not on the settings panel: left-clicking the block toggles it,
-- and /fp xp does the same, so a checkbox would be a third way to say it.

--- Progress through the current level, as "xx.xx% XP" counting up or
-- "xx.xx% left" counting down.
-- Returns nil when there is no XP bar to describe (max level, or XP turned
-- off), which tells the module to hide itself.
local function formatXP(xp, xpMax, countDown)
    xp = tonumber(xp) or 0
    xpMax = tonumber(xpMax) or 0

    if xpMax <= 0 then
        return nil
    end

    local earned = math.min(xpMax, math.max(0, xp))

    if countDown then
        return string.format("%.2f%% left", (xpMax - earned) / xpMax * 100)
    end

    return string.format("%.2f%% XP", earned / xpMax * 100)
end

ns.FormatXP = formatXP

ns.Bar:RegisterModule({
    name = "xp",
    side = "LEFT",
    order = 30,
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
        local text = not disabled
            and formatXP(UnitXP("player"), UnitXPMax("player"), ns.db.xp.countDown)
            or nil

        if not text then
            module:SetShown(false)
            return
        end

        module.text:SetText(text)
        module:SetWidth(module.text:GetStringWidth())
        module:SetShown(true)
    end,

    OnClick = function(module, button)
        if button == "LeftButton" then
            ns.db.xp.countDown = not ns.db.xp.countDown
            module:Refresh()
        end
    end,
})

ns.RegisterCommand("xp", "Toggle the XP block between counting up and counting down", function()
    ns.db.xp.countDown = not ns.db.xp.countDown

    local module = ns.Bar:GetModule("xp")
    if module then
        module:Refresh()
    end

    ns.Print(string.format(
        "XP now counts %s.",
        ns.db.xp.countDown and "down to the next level" or "up from the last one"
    ))
end)
