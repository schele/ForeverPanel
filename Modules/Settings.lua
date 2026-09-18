local addonName, ns = ...

-- The settings panel. Everything on it comes from ns.RegisterSetting, so this
-- file never needs editing when a module gains a setting: it renders whatever
-- has been declared, in declaration order.

local PADDING = 16
local ROW_HEIGHT = 30
local SLIDER_EXTRA = 20
local INDENT = 24

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
    line:SetPoint("TOPLEFT", PADDING, y)
    line:SetPoint("TOPRIGHT", -PADDING, y)

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

local function build()
    panel = CreateFrame("Frame")
    panel.name = "ForeverPanel"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", PADDING, -PADDING)
    title:SetText("ForeverPanel")

    local y = -PADDING - ROW_HEIGHT
    for index, group in ipairs(groupedSettings()) do
        if index > 1 and #group > 0 then
            y = y - ROW_HEIGHT / 2
            addDivider(y)
            y = y - ROW_HEIGHT / 2
        end

        for _, row in ipairs(group) do
            local setting = row.setting
            local indent = PADDING + row.depth * INDENT

            local control
            if setting.type == "slider" then
                control = addSlider(setting, y, indent)
                y = y - ROW_HEIGHT - SLIDER_EXTRA
            else
                control = addCheckbox(setting, y, indent)
                y = y - ROW_HEIGHT
            end

            control.depth = row.depth
            table.insert(Settings_.controls, control)
        end
    end

    panel:SetScript("OnShow", Settings_.Refresh)

    -- A canvas category holds widgets we own, which avoids
    -- Settings.RegisterAddOnSetting: its argument list changed in 11.0 and a
    -- wrong guess there registers nothing and fails silently.
    category = Settings.RegisterCanvasLayoutCategory(panel, "ForeverPanel")
    Settings.RegisterAddOnCategory(category)

    Settings_.Refresh()
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
        build()
    else
        ns.Print("This client has no settings panel API. Use /fp for commands instead.")
    end
end)
