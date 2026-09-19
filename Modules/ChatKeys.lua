local addonName, ns = ...

-- Keys that open the chat box with a command already typed. Ctrl+S for /say and
-- so on, configurable from the settings panel.

local ROWS = 8

-- A working set out of the box. It matters more than it usually would: this
-- client restores SavedVariables for no addon, so without these the table is
-- empty every login.
local SEED = {
    { key = "CTRL-S", command = "/say" },
    { key = "CTRL-G", command = "/g" },
    { key = "CTRL-T", command = "/trade" },
    { key = "CTRL-Y", command = "/yell" },
    { key = "CTRL-P", command = "/p" },
}

ns.AddDefaults({
    chat = {
        -- On by default: this client discards SavedVariables, so anything off
        -- by default is off at every login. Turned off, nothing here is
        -- created at all, which is what makes the switch worth having.
        enabled = true,
        keys = {},
        seeded = false,
    },
})

local ChatKeys = {}
ns.ChatKeys = ChatKeys
ChatKeys.ROWS = ROWS

local owner = CreateFrame("Frame", nil, UIParent)
local buttons = {}
local pending = false

--- Build a binding string from a key and whatever modifiers are held.
-- Returns nil for a key that cannot stand on its own, so the capture keeps
-- waiting rather than binding "CTRL-" to something.
function ChatKeys.Combination(key)
    if not key or key == "ESCAPE" or key == "UNKNOWN" then
        return nil
    end

    -- A modifier pressed by itself is the player reaching for the combination,
    -- not the combination.
    if key:match("^[LR]CTRL$") or key:match("^[LR]SHIFT$") or key:match("^[LR]ALT$") then
        return nil
    end

    -- WoW writes them in this order, and matching it is what makes the string
    -- usable as a binding.
    local prefix = ""
    if IsAltKeyDown and IsAltKeyDown() then
        prefix = prefix .. "ALT-"
    end
    if IsControlKeyDown and IsControlKeyDown() then
        prefix = prefix .. "CTRL-"
    end
    if IsShiftKeyDown and IsShiftKeyDown() then
        prefix = prefix .. "SHIFT-"
    end

    -- A bare key takes that key everywhere: bind "B" and bags stop opening,
    -- bind a movement key and the character stops moving. Function keys are
    -- the exception, being nobody else's by default.
    if prefix == "" and not key:match("^F%d+$") then
        return nil
    end

    return prefix .. key
end

local function openChat(command)
    if not ChatFrame_OpenChat then
        ns.Print("This client has no chat box to open.")
        return
    end

    -- Trailing space so the cursor lands after the command, ready to type.
    ChatFrame_OpenChat((command:gsub("%s+$", "")) .. " ")
end

local function rowFor(index)
    local rows = ns.db and ns.db.chat and ns.db.chat.keys
    return rows and rows[index]
end

--- Build the buttons the bindings click, the first time they are needed.
-- Nothing exists while the feature is off: no frames, no bindings, no scripts.
-- That makes "off" mean genuinely absent rather than merely inactive, which is
-- the only way to tell whether this feature is behind a problem or not.
local function ensureButtons()
    if buttons[1] then
        return
    end

    for index = 1, ROWS do
        local button = CreateFrame("Button", "ForeverPanelChatKey" .. index, UIParent)
        button:RegisterForClicks("AnyDown")
        button:Hide()
        button:SetScript("OnClick", function()
            local row = rowFor(index)
            if row and row.command and row.command ~= "" then
                openChat(row.command)
            end
        end)
        buttons[index] = button
    end
end

--- Put every filled row on its key.
-- Override bindings layer on top of the player's own, so nothing they have set
-- is edited or lost, and a reload clears ours.
function ChatKeys.Apply()
    if not SetOverrideBindingClick or not ClearOverrideBindings then
        return false
    end

    -- Bindings are protected in combat. Hold the change rather than erroring,
    -- and put it on when the fight ends.
    if InCombatLockdown and InCombatLockdown() then
        pending = true
        return false
    end

    pending = false
    ClearOverrideBindings(owner)

    if ns.db.chat.enabled then
        ensureButtons()

        for index = 1, ROWS do
            local row = rowFor(index)
            if row and row.key and row.key ~= "" and row.command and row.command ~= "" then
                SetOverrideBindingClick(owner, true, row.key, "ForeverPanelChatKey" .. index)
            end
        end
    end

    return true
end

--- Drop every binding we hold, without changing the table.
-- The way out if ours are the ones swallowing keys.
function ChatKeys.ReleaseBindings()
    if ClearOverrideBindings then
        ClearOverrideBindings(owner)
    end
end

ns.RegisterSetting({
    store = "chat",
    key = "enabled",
    type = "checkbox",
    column = 2,
    name = "Chat shortcut keys",
    tooltip = "Ctrl+S for /say and so on. Off by default while a keyboard capture problem is outstanding.",
    onChange = ChatKeys.Apply,
})

ns.RegisterSetting({
    store = "chat",
    key = "keys",
    type = "keytable",
    parent = "chat.enabled",
    name = "Chat shortcuts",
    -- Its own column: eight rows down the left would push everything else off
    -- the bottom of the panel.
    column = 2,
    rows = ROWS,
    onChange = ChatKeys.Apply,
})

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("PLAYER_ENTERING_WORLD")
loader:RegisterEvent("PLAYER_REGEN_ENABLED")
loader:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        if not ns.db.chat.seeded then
            ns.db.chat.seeded = true
            for index, entry in ipairs(SEED) do
                ns.db.chat.keys[index] = { key = entry.key, command = entry.command }
            end
        end

        for index = 1, ROWS do
            ns.db.chat.keys[index] = ns.db.chat.keys[index] or { key = "", command = "" }
        end

        ChatKeys.Apply()
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- The binding set has loaded by now, so this is the one that sticks.
        ChatKeys.Apply()
    elseif event == "PLAYER_REGEN_ENABLED" and pending then
        ChatKeys.Apply()
    end
end)
