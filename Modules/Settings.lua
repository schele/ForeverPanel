local addonName, ns = ...

-- The settings panel. Everything on it comes from ns.RegisterSetting, so this
-- file never needs editing when a module gains a setting: it renders whatever
-- has been declared, in declaration order.

local PADDING = 16
local ROW_HEIGHT = 30
local SLIDER_EXTRA = 20
local INDENT = 24
-- Two columns, each with its own vertical cursor. A setting says which it wants
-- with `column`; the chat table goes right so it does not push everything else
-- off the bottom of the panel.
local COLUMN_WIDTH = 280
local COLUMN_X = { PADDING, PADDING + COLUMN_WIDTH + 24 }

local Settings_ = {}
ns.Settings = Settings_
Settings_.controls = {}
Settings_.dividers = {}

local panel, category

local function addCheckbox(setting, y, indent)
    local button = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    button:SetPoint("TOPLEFT", indent or PADDING, y)

    -- The label belongs to the template on some clients and not others, so
    -- write our own rather than reaching for button.Text and finding nil.
    local label = button:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("LEFT", button, "RIGHT", 4, 0)
    label:SetText(setting.name)

    button:SetScript("OnClick", function(self)
        ns.SetSettingValue(setting, self:GetChecked() and true or false)
    end)

    return {
        setting = setting,
        widget = button,
        Refresh = function()
            button:SetChecked(ns.SettingValue(setting) and true or false)
        end,
    }
end

local function addSlider(setting, y, indent)
    local slider = CreateFrame("Slider", nil, panel, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", indent or PADDING, y - SLIDER_EXTRA)
    slider:SetMinMaxValues(setting.min, setting.max)
    slider:SetValueStep(setting.step or 1)
    slider:SetObeyStepOnDrag(true)
    slider:SetWidth(200)

    -- The template labels its ends "Low" and "High", which says nothing about
    -- the range. Show the actual numbers where the template exposes them.
    if slider.Low and slider.Low.SetText then
        slider.Low:SetText(tostring(setting.min))
    end
    if slider.High and slider.High.SetText then
        slider.High:SetText(tostring(setting.max))
    end

    local label = slider:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("BOTTOMLEFT", slider, "TOPLEFT", 0, 4)

    local function relabel(value)
        label:SetText(string.format("%s: %d", setting.name, value or 0))
    end

    slider:SetScript("OnValueChanged", function(_, value)
        value = math.floor(value + 0.5)
        relabel(value)
        ns.SetSettingValue(setting, value)
    end)

    return {
        setting = setting,
        widget = slider,
        Refresh = function()
            local value = ns.SettingValue(setting)
            slider:SetValue(value)
            relabel(value)
        end,
    }
end

--- A table of key/command pairs, each row a capture box and an edit box.
-- The capture box takes the next combination pressed rather than having the
-- player type WoW's binding syntax, where a typo just silently fails to bind.
-- Only one capture box listens at a time, and it stops the moment focus moves.
-- A box left listening swallows ordinary typing: entering "/" is Shift+7 on
-- some layouts, which would rebind the row instead of typing a slash.
local armedCapture

-- Every edit box on the panel, so focus can be dropped wholesale. A box left
-- focused, or a capture left listening, swallows the entire keyboard: no key
-- reaches the game, not even Escape.
local focusables = {}

--- Let keys we are not interested in carry on to the rest of the UI.
-- A frame with an OnKeyDown script consumes the key unless it says otherwise.
-- Printable characters reach a focused edit box by a different path, so
-- without this the panel could be typed into but not erased or escaped from.
local function passKeysThrough(frame, pass)
    if frame.SetPropagateKeyboardInput then
        frame:SetPropagateKeyboardInput(pass and true or false)
    end
end

local function disarmCapture()
    if not armedCapture then
        return
    end
    local previous = armedCapture
    armedCapture = nil
    previous.frame:EnableKeyboard(false)
    passKeysThrough(previous.frame, true)
    previous.relabel()
end

local function addKeyTable(setting, y, indent)
    local rows = {}

    -- A table hung under a checkbox is already labelled by it.
    if not setting.parent then
        local header = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        header:SetPoint("TOPLEFT", indent, y)
        header:SetText(setting.name)
        y = y - ROW_HEIGHT
    end

    for index = 1, (setting.rows or 6) do
        local capture = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        capture:SetPoint("TOPLEFT", indent, y)
        capture:SetSize(110, 22)
        capture:EnableKeyboard(false)
        passKeysThrough(capture, true)

        local command = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
        command:SetPoint("TOPLEFT", indent + 122, y)
        command:SetSize(130, 22)
        -- Both, and in this order. An EditBox grabs focus as it comes into
        -- existence, so SetAutoFocus(false) is a line too late to prevent it
        -- and the box has to be told to let go of what it already took.
        command:SetAutoFocus(false)
        command:ClearFocus()
        table.insert(focusables, command)

        local function entry()
            local list = ns.SettingValue(setting)
            list[index] = list[index] or { key = "", command = "" }
            return list[index]
        end

        local function label()
            local text = entry().key
            capture:SetText(text ~= "" and text or "Set key")
        end

        capture:SetScript("OnClick", function(self)
            disarmCapture()
            armedCapture = { frame = self, relabel = label }
            self:SetText("press a key")
            self:EnableKeyboard(true)
            passKeysThrough(self, false)
        end)

        capture:SetScript("OnKeyDown", function(self, key)
            if armedCapture == nil or armedCapture.frame ~= self then
                -- Not ours to take: hand it on rather than swallow it.
                passKeysThrough(self, true)
                return
            end

            local combination = ns.ChatKeys.Combination(key)
            if not combination then
                -- Escape or a lone modifier: give up rather than bind nothing.
                if key == "ESCAPE" then
                    disarmCapture()
                end
                return
            end

            entry().key = combination
            disarmCapture()
            if setting.onChange then
                setting.onChange()
            end
        end)

        command:SetScript("OnEditFocusGained", disarmCapture)

        command:SetScript("OnEditFocusLost", function(self)
            entry().command = self:GetText() or ""
            if setting.onChange then
                setting.onChange()
            end
        end)
        command:SetScript("OnEnterPressed", function(self)
            self:ClearFocus()
        end)

        -- Without this the focused box eats Escape and the options window
        -- refuses to close. Escape abandons the edit, as it does elsewhere.
        command:SetScript("OnEscapePressed", function(self)
            self:SetText(entry().command or "")
            self:ClearFocus()
        end)

        table.insert(rows, {
            index = index,
            capture = capture,
            command = command,
            Refresh = function()
                label()
                command:SetText(entry().command or "")
            end,
        })

        y = y - ROW_HEIGHT
    end

    return {
        setting = setting,
        widget = rows[1] and rows[1].capture,
        rows = rows,
        height = ROW_HEIGHT * ((setting.rows or 6) + (setting.parent and 0 or 1)),
        Refresh = function()
            for _, row in ipairs(rows) do
                row.Refresh()
            end
        end,
    }
end

--- Hand the keyboard back to the game.
-- Called whenever the panel is shown or hidden, because a widget that still
-- holds it leaves the player unable to move, open bags, or press Escape.
function Settings_.ReleaseKeyboard()
    disarmCapture()
    for _, box in ipairs(focusables) do
        box:ClearFocus()
    end
end

--- Say what is holding the keyboard, then let go of everything.
-- Reachable from the right-click menu because when the keyboard is captured a
-- slash command cannot be typed, which is exactly when this is needed.
function ns.ReportKeyboard()
    local focus = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
    local focusName = "none"
    if focus then
        focusName = (focus.GetName and focus:GetName()) or "an unnamed frame"
        local parent = focus.GetParent and focus:GetParent()
        if parent then
            focusName = focusName .. " in " .. ((parent.GetName and parent:GetName()) or "an unnamed parent")
        end
    end

    ns.Print("keyboard focus: " .. focusName)
    -- IsVisible, not IsShown: a child of a hidden parent still reports itself
    -- shown, which made this line read as an anomaly when it was not one.
    ns.Print(string.format(
        "capture armed: %s | our panel visible: %s | settings visible: %s",
        armedCapture and "yes" or "no",
        panel and tostring(panel:IsVisible()) or "no panel",
        SettingsPanel and tostring(SettingsPanel:IsVisible()) or "no SettingsPanel"
    ))

    local bound = {}
    for index = 1, (ns.ChatKeys and ns.ChatKeys.ROWS or 0) do
        local row = ns.db.chat.keys[index]
        if row and row.key ~= "" and row.command ~= "" then
            table.insert(bound, row.key .. "=" .. row.command)
        end
    end
    ns.Print("bound: " .. (#bound > 0 and table.concat(bound, ", ") or "nothing"))

    -- Now hand everything back, so this also serves as the way out.
    Settings_.ReleaseKeyboard()
    if ns.ChatKeys and ns.ChatKeys.ReleaseBindings then
        ns.ChatKeys.ReleaseBindings()
    end
    ns.Print("Released keyboard focus and cleared our key bindings.")
end

--- Push the stored values back into the controls.
-- Called when the panel opens, because the same settings can be changed from
-- the right-click menu or a slash command while it is shut.
function Settings_.Refresh()
    for _, control in ipairs(Settings_.controls) do
        control.Refresh()
    end
end

local function addDivider(y)
    local line = panel:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 1, 1, 0.15)
    line:SetHeight(1)
    -- Only as wide as the first column, so it does not cut across the second.
    line:SetPoint("TOPLEFT", COLUMN_X[1], y)
    line:SetWidth(COLUMN_WIDTH)

    table.insert(Settings_.dividers, line)
    return line
end

--- Order the settings, placing any that name a parent directly under it.
-- Returns { setting, depth, section } rows. A child follows its parent
-- wherever the parent ended up, and shares its group, so declaration order
-- across files does not matter.
local function orderedRows()
    local byKey, childrenOf, roots = {}, {}, {}

    for _, setting in ipairs(ns.settings) do
        byKey[setting.store .. "." .. setting.key] = setting
    end

    for _, setting in ipairs(ns.settings) do
        local parent = setting.parent and byKey[setting.parent]
        if parent then
            childrenOf[setting.parent] = childrenOf[setting.parent] or {}
            table.insert(childrenOf[setting.parent], setting)
        else
            table.insert(roots, setting)
        end
    end

    local rows = {}
    for _, setting in ipairs(roots) do
        table.insert(rows, { setting = setting, depth = 0, section = setting.section })

        local key = setting.store .. "." .. setting.key
        for _, child in ipairs(childrenOf[key] or {}) do
            table.insert(rows, { setting = child, depth = 1, section = setting.section })
        end
    end

    return rows
end

--- Split the ordered rows into display groups.
-- Anything with no section comes first, then each section in the order it was
-- first seen, which is .toc order. A divider goes between groups.
local function groupedSettings()
    local main, bySection, order = {}, {}, {}

    for _, row in ipairs(orderedRows()) do
        local section = row.section
        if not section then
            table.insert(main, row)
        else
            if not bySection[section] then
                bySection[section] = {}
                table.insert(order, section)
            end
            table.insert(bySection[section], row)
        end
    end

    local groups = { main }
    for _, section in ipairs(order) do
        table.insert(groups, bySection[section])
    end
    return groups
end

local built = false

--- Create the controls, the first time the panel is actually opened.
-- Nothing here exists at login: no edit boxes, no buttons, no frames beyond the
-- empty canvas itself. Widgets that exist before anyone asks for them were
-- eating keystrokes from login, and the surest fix is not to build them.
local function ensureBuilt()
    if built then
        return
    end
    built = true

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", PADDING, -PADDING)
    title:SetText("ForeverPanel")

    -- From the addon's own metadata, not a constant here, which would drift
    -- from the .toc the first time either is bumped without the other.
    local metadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local version = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    version:SetPoint("LEFT", title, "RIGHT", 8, -2)
    version:SetText("Version " .. ((metadata and metadata(addonName, "Version")) or "unknown"))
    Settings_.version = version

    local top = -PADDING - ROW_HEIGHT
    local cursor = { top, top }

    for index, group in ipairs(groupedSettings()) do
        local usesFirstColumn = false
        for _, row in ipairs(group) do
            usesFirstColumn = usesFirstColumn or (row.setting.column or 1) == 1
        end

        if index > 1 and usesFirstColumn then
            cursor[1] = cursor[1] - ROW_HEIGHT / 2
            addDivider(cursor[1])
            cursor[1] = cursor[1] - ROW_HEIGHT / 2
        end

        for _, row in ipairs(group) do
            local setting = row.setting
            local column = setting.column or 1
            local indent = COLUMN_X[column] + row.depth * INDENT
            local y = cursor[column]

            local control
            if setting.type == "slider" then
                control = addSlider(setting, y, indent)
                cursor[column] = y - ROW_HEIGHT - SLIDER_EXTRA
            elseif setting.type == "keytable" then
                control = addKeyTable(setting, y, indent)
                cursor[column] = y - control.height
            else
                control = addCheckbox(setting, y, indent)
                cursor[column] = y - ROW_HEIGHT
            end

            control.depth = row.depth
            table.insert(Settings_.controls, control)
        end
    end

    Settings_.Refresh()
end

Settings_.EnsureBuilt = ensureBuilt

--- Claim a place in the game's options, without building anything yet.
local function register()
    -- Parented and hidden. Left parentless and shown, as the canvas examples
    -- suggest, the frame is live on screen from login. The Settings system
    -- shows it when the category is opened, and that is when it gets filled.
    panel = CreateFrame("Frame", nil, UIParent)
    panel:Hide()
    panel.name = "ForeverPanel"
    Settings_.panel = panel

    panel:SetScript("OnShow", function()
        ensureBuilt()
        Settings_.ReleaseKeyboard()
        Settings_.Refresh()
    end)

    -- Closing the panel with a box still focused would otherwise leave the
    -- keyboard captured with nothing on screen to explain why.
    panel:SetScript("OnHide", Settings_.ReleaseKeyboard)

    -- A canvas category holds widgets we own, which avoids
    -- Settings.RegisterAddOnSetting: its argument list changed in 11.0 and a
    -- wrong guess there registers nothing and fails silently.
    category = Settings.RegisterCanvasLayoutCategory(panel, "ForeverPanel")
    Settings.RegisterAddOnCategory(category)
end

-- Whether the panel currently on screen was opened from our menu rather than
-- through the game menu. Decides where closing it should leave the player.
local openedByUs = false

-- Armed while the client is closing a panel we opened, so the game menu it
-- puts up on the way out can be turned away at the door.
local suppressGameMenu = false

local function dismissGameMenu(frame)
    suppressGameMenu = false
    if HideUIPanel then
        HideUIPanel(frame)
    else
        frame:Hide()
    end
end

local function watchForClose()
    if Settings_.closeHooked or not SettingsPanel or not SettingsPanel.HookScript then
        return
    end
    Settings_.closeHooked = true

    SettingsPanel:HookScript("OnHide", function()
        -- Opening the panel programmatically leaves the client queued to fall
        -- back to the game menu, which is not where the player came from. Only
        -- dismiss it when we were the ones who opened the panel.
        if not openedByUs then
            return
        end
        openedByUs = false
        suppressGameMenu = true

        -- Backstop, in case the menu is already up or has no OnShow to catch:
        -- hides it a frame later, which flashes but is better than leaving it.
        -- Does nothing if the hook below already dealt with it.
        C_Timer.After(0, function()
            if suppressGameMenu then
                if GameMenuFrame and GameMenuFrame:IsShown() then
                    dismissGameMenu(GameMenuFrame)
                end
                suppressGameMenu = false
            end
        end)
    end)

    -- Catching it as it shows means it never reaches the screen, where hiding
    -- it afterwards let the player see it for a frame.
    if GameMenuFrame and GameMenuFrame.HookScript then
        GameMenuFrame:HookScript("OnShow", function(self)
            if suppressGameMenu then
                dismissGameMenu(self)
            end
        end)
    end
end

--- Open the panel in the game's options window.
function ns.OpenSettings()
    if not category then
        return
    end

    watchForClose()
    openedByUs = true

    -- Build before showing, in case the client opens the category without
    -- firing OnShow on our canvas.
    ensureBuilt()

    Settings.OpenToCategory(category:GetID())
    Settings_.Refresh()
end

ns.RegisterCommand("settings", "Open the settings panel", function()
    ns.OpenSettings()
end)

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")

    if Settings and Settings.RegisterCanvasLayoutCategory then
        register()
    else
        ns.Print("This client has no settings panel API. Use /fp for commands instead.")
    end
end)
