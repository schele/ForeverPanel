local addonName, ns = ...

ns.AddDefaults({
    clock = {
        use24Hour = true,
        hideBlizzardClock = true,
    },
})

--- Format a wall-clock time. Pure, so it is unit tested directly.
local function formatClock(hour, minute, use24Hour)
    hour = math.floor(tonumber(hour) or 0) % 24
    minute = math.floor(tonumber(minute) or 0) % 60

    if use24Hour then
        return string.format("%02d:%02d", hour, minute)
    end

    local suffix = hour < 12 and "AM" or "PM"
    local hour12 = hour % 12
    if hour12 == 0 then
        hour12 = 12
    end

    return string.format("%d:%02d %s", hour12, minute, suffix)
end

ns.FormatClock = formatClock

--------------------------------------------------------------------------------
-- Blizzard's clock
--------------------------------------------------------------------------------

local hookInstalled = false

--- Show or hide Blizzard's own clock, reversibly.
-- Hiding is done with Hide plus a Show hook rather than reparenting, so the
-- Time Manager keeps working (alarms, the stopwatch) and toggling the setting
-- back on restores the button.
local function updateBlizzardClock()
    local button = TimeManagerClockButton
    if not button then
        return false
    end

    if not hookInstalled then
        hookInstalled = true
        hooksecurefunc(button, "Show", function(self)
            if ns.db and ns.db.clock.hideBlizzardClock then
                self:Hide()
            end
        end)
    end

    if ns.db.clock.hideBlizzardClock then
        button:Hide()
    else
        button:Show()
    end

    return true
end

ns.UpdateBlizzardClock = updateBlizzardClock

-- Blizzard_TimeManager can be load-on-demand, so the button may not exist yet.
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("ADDON_LOADED")
watcher:SetScript("OnEvent", function(self)
    if TimeManagerClockButton and ns.db and updateBlizzardClock() then
        self:UnregisterEvent("ADDON_LOADED")
    end
end)

--------------------------------------------------------------------------------
-- Module
--------------------------------------------------------------------------------

local function retextClock(module)
    local now = date("*t")
    local text = formatClock(now.hour, now.min, ns.db.clock.use24Hour)

    -- Only touch the font string when the text actually changes, so a 1 second
    -- ticker does not dirty the layout every tick.
    if text ~= module.lastText then
        module.lastText = text
        module.text:SetText(text)
        module:SetWidth(module.text:GetStringWidth())
    end
end

ns.Bar:RegisterModule({
    name = "clock",
    side = "CENTER",
    order = 10,
    interval = 1,
    events = { "PLAYER_ENTERING_WORLD" },

    OnCreate = function(module)
        module.text = module.frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        module.text:SetPoint("LEFT")
        updateBlizzardClock()
    end,

    OnUpdate = retextClock,

    OnClick = function(module, button)
        if button == "LeftButton" then
            ns.db.clock.use24Hour = not ns.db.clock.use24Hour
            module.lastText = nil
            module:Refresh()
        end
    end,
})

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------

ns.RegisterCommand("clock", "Toggle 12/24 hour time. Also: clock blizzard", function(rest)
    local argument = ((rest or ""):match("^(%S*)") or ""):lower()

    if argument == "blizzard" then
        ns.db.clock.hideBlizzardClock = not ns.db.clock.hideBlizzardClock
        updateBlizzardClock()
        ns.Print(string.format(
            "Blizzard's clock is now %s.",
            ns.db.clock.hideBlizzardClock and "hidden" or "shown"
        ))
    elseif argument == "" then
        ns.db.clock.use24Hour = not ns.db.clock.use24Hour

        local module = ns.Bar:GetModule("clock")
        if module then
            module.lastText = nil
            module:Refresh()
        end

        ns.Print(string.format(
            "Clock set to %s hour time.",
            ns.db.clock.use24Hour and "24" or "12"
        ))
    else
        ns.Print(string.format("Unknown clock option: %s", argument))
    end
end)
