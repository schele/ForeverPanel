local addonName, ns = ...

local Bar = {}
ns.Bar = Bar

ns.AddDefaults({
    bar = {
        enabled = true,
        height = 24,
        pushUIDown = true,
    },
})

local VALID_SIDES = { LEFT = true, CENTER = true, RIGHT = true }
local EDGE_PADDING = 10
local MODULE_SPACING = 16
local MIN_HEIGHT, MAX_HEIGHT = 16, 48

local modules = {}
local modulesByName = {}
local eventMap = {}
local barFrame, dispatcher
local initialized = false
local layoutQueued = false

--------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------

--- Work out where every visible module sits on the bar.
-- Pure function of the module list, so it can be unit tested directly.
-- LEFT flows left-to-right from the left edge, RIGHT flows right-to-left from
-- the right edge, CENTER is laid out as one group centred on the bar. Hidden
-- modules are dropped entirely, taking their spacing with them.
local function computeLayout(entries, options)
    options = options or {}
    local padding = options.padding or EDGE_PADDING
    local spacing = options.spacing or MODULE_SPACING

    local bySide = { LEFT = {}, CENTER = {}, RIGHT = {} }
    for _, entry in ipairs(entries) do
        if entry.shown ~= false and VALID_SIDES[entry.side] then
            table.insert(bySide[entry.side], entry)
        end
    end

    local function byOrder(a, b)
        if a.order ~= b.order then
            return a.order < b.order
        end
        return a.name < b.name
    end

    for _, list in pairs(bySide) do
        table.sort(list, byOrder)
    end

    local positions = {}

    local offset = padding
    for _, entry in ipairs(bySide.LEFT) do
        positions[entry.name] = { anchor = "LEFT", offset = offset }
        offset = offset + (entry.width or 0) + spacing
    end

    offset = padding
    for _, entry in ipairs(bySide.RIGHT) do
        positions[entry.name] = { anchor = "RIGHT", offset = -offset }
        offset = offset + (entry.width or 0) + spacing
    end

    local total = 0
    for index, entry in ipairs(bySide.CENTER) do
        total = total + (entry.width or 0)
        if index > 1 then
            total = total + spacing
        end
    end

    local cursor = -total / 2
    for _, entry in ipairs(bySide.CENTER) do
        local width = entry.width or 0
        positions[entry.name] = { anchor = "CENTER", offset = cursor + width / 2 }
        cursor = cursor + width + spacing
    end

    return positions
end

Bar.ComputeLayout = computeLayout

local function applyLayout()
    layoutQueued = false
    if not barFrame then
        return
    end

    local positions = computeLayout(modules)
    for _, module in ipairs(modules) do
        local frame = module.frame
        if frame then
            local position = positions[module.name]
            if position then
                frame:ClearAllPoints()
                frame:SetPoint(position.anchor, barFrame, position.anchor, position.offset, 0)
                frame:Show()
            else
                frame:Hide()
            end
        end
    end
end

Bar.ApplyLayout = applyLayout

--- Coalesce many layout requests in the same frame into a single reflow.
local function queueLayout()
    if layoutQueued or not barFrame then
        return
    end
    layoutQueued = true
    C_Timer.After(0, applyLayout)
end

--------------------------------------------------------------------------------
-- Module objects
--------------------------------------------------------------------------------

local moduleProto = {}
local moduleMeta = { __index = moduleProto }

function moduleProto:MarkDirty()
    queueLayout()
end

function moduleProto:SetWidth(width)
    width = math.max(0, math.floor((tonumber(width) or 0) + 0.5))
    if width == self.width then
        return
    end
    self.width = width
    if self.frame then
        self.frame:SetWidth(math.max(width, 1))
    end
    self:MarkDirty()
end

function moduleProto:SetShown(shown)
    shown = shown and true or false
    if shown == self.shown then
        return
    end
    self.shown = shown
    self:MarkDirty()
end

function moduleProto:Refresh()
    if self.frame and self.OnUpdate then
        self:OnUpdate()
    end
end

--------------------------------------------------------------------------------
-- Registry
--------------------------------------------------------------------------------

local function subscribe(module)
    if not module.events then
        return
    end

    for _, event in ipairs(module.events) do
        local list = eventMap[event]
        if not list then
            list = {}
            eventMap[event] = list
            if dispatcher then
                dispatcher:RegisterEvent(event)
            end
        end
        table.insert(list, module)
    end
end

local function createModuleFrame(module)
    if module.frame or not barFrame then
        return
    end

    local frame = CreateFrame("Button", nil, barFrame)
    frame:SetHeight(ns.db.bar.height)
    frame:SetWidth(math.max(module.width, 1))
    frame:RegisterForClicks("AnyUp")
    module.frame = frame

    if module.OnClick then
        frame:SetScript("OnClick", function(_, button)
            module:OnClick(button)
        end)
    end

    if module.OnEnter then
        frame:SetScript("OnEnter", function()
            module:OnEnter()
        end)
    end

    if module.OnLeave then
        frame:SetScript("OnLeave", function()
            module:OnLeave()
        end)
    end

    if module.OnCreate then
        module:OnCreate()
    end

    if module.interval then
        module.ticker = C_Timer.NewTicker(module.interval, function()
            module:Refresh()
        end)
    end

    module:Refresh()
end

--- Register an info block on the bar.
-- The bar owns the frame, layout and event plumbing; a module only describes
-- itself and fills in its own content.
function Bar:RegisterModule(definition)
    assert(type(definition) == "table", "RegisterModule expects a table")

    local name = definition.name
    assert(type(name) == "string" and name ~= "", "module requires a name")
    assert(not modulesByName[name], "duplicate module name: " .. tostring(name))

    local side = definition.side or "LEFT"
    assert(VALID_SIDES[side], "invalid side: " .. tostring(side))

    local module = setmetatable({
        name = name,
        side = side,
        order = definition.order or 100,
        events = definition.events,
        interval = definition.interval,
        width = definition.width or 0,
        shown = true,
        OnCreate = definition.OnCreate,
        OnUpdate = definition.OnUpdate,
        OnClick = definition.OnClick,
        OnEnter = definition.OnEnter,
        OnLeave = definition.OnLeave,
    }, moduleMeta)

    modulesByName[name] = module
    table.insert(modules, module)
    subscribe(module)

    -- Modules registered after login still get built.
    if initialized then
        createModuleFrame(module)
        queueLayout()
    end

    return module
end

function Bar:GetModule(name)
    return modulesByName[name]
end

function Bar:RefreshAll()
    for _, module in ipairs(modules) do
        module:Refresh()
    end
end

--------------------------------------------------------------------------------
-- Screen space
--------------------------------------------------------------------------------

--- Shrink UIParent from the top so every top-anchored Blizzard frame moves
-- down with it. Wrapped in pcall: if a future patch makes this fail, the bar
-- still works as an overlay instead of breaking the UI.
local function applyUIParentInset()
    local config = ns.db.bar
    local inset = (config.enabled and config.pushUIDown) and config.height or 0

    local ok = pcall(function()
        UIParent:ClearAllPoints()
        UIParent:SetPoint("TOPLEFT", nil, "TOPLEFT", 0, -inset)
        UIParent:SetPoint("BOTTOMRIGHT", nil, "BOTTOMRIGHT", 0, 0)
    end)

    if not ok then
        ns.Print("Could not reserve space at the top of the screen. Use /forever bar push to turn this off.")
    end

    return ok
end

Bar.ApplyUIParentInset = applyUIParentInset

local function anchorBar()
    if not barFrame then
        return
    end

    local config = ns.db.bar
    barFrame:ClearAllPoints()

    if config.pushUIDown then
        -- Sit in the strip that applyUIParentInset just freed up.
        barFrame:SetPoint("BOTTOMLEFT", UIParent, "TOPLEFT", 0, 0)
        barFrame:SetPoint("BOTTOMRIGHT", UIParent, "TOPRIGHT", 0, 0)
    else
        barFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
        barFrame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", 0, 0)
    end

    barFrame:SetHeight(config.height)

    for _, module in ipairs(modules) do
        if module.frame then
            module.frame:SetHeight(config.height)
        end
    end
end

function Bar:Update()
    applyUIParentInset()
    anchorBar()

    if barFrame then
        barFrame:SetShown(ns.db.bar.enabled)
    end

    applyLayout()
end

--------------------------------------------------------------------------------
-- Setup
--------------------------------------------------------------------------------

function Bar:Initialize()
    if initialized then
        return
    end
    initialized = true

    barFrame = CreateFrame("Frame", "ForeverBar", UIParent)
    barFrame:SetFrameStrata("MEDIUM")

    local background = barFrame:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0, 0, 0, 0.8)
    barFrame.background = background

    self.frame = barFrame

    dispatcher = CreateFrame("Frame")
    dispatcher:SetScript("OnEvent", function(_, event, ...)
        if event == "DISPLAY_SIZE_CHANGED" or event == "UI_SCALE_CHANGED" then
            Bar:Update()
        end

        local list = eventMap[event]
        if list then
            for _, module in ipairs(list) do
                module:Refresh()
            end
        end
    end)

    dispatcher:RegisterEvent("DISPLAY_SIZE_CHANGED")
    dispatcher:RegisterEvent("UI_SCALE_CHANGED")
    for event in pairs(eventMap) do
        dispatcher:RegisterEvent(event)
    end

    for _, module in ipairs(modules) do
        createModuleFrame(module)
    end

    self:Update()
end

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------

ns.RegisterCommand("bar", "Toggle the top bar. Also: bar height <16-48>, bar push", function(rest)
    local argument, value = (rest or ""):match("^(%S*)%s*(.-)$")
    argument = argument:lower()
    local config = ns.db.bar

    if argument == "height" then
        local height = tonumber(value)
        if not height then
            ns.Print(string.format("Bar height is %d. Usage: /forever bar height <%d-%d>", config.height, MIN_HEIGHT, MAX_HEIGHT))
            return
        end

        config.height = math.max(MIN_HEIGHT, math.min(MAX_HEIGHT, math.floor(height)))
        Bar:Update()
        Bar:RefreshAll()
        ns.Print(string.format("Bar height set to %d.", config.height))
    elseif argument == "push" then
        config.pushUIDown = not config.pushUIDown
        Bar:Update()
        ns.Print(string.format("Pushing the UI down is now %s.", config.pushUIDown and "on" or "off"))
    elseif argument == "" then
        config.enabled = not config.enabled
        Bar:Update()
        ns.Print(string.format("Top bar %s.", config.enabled and "shown" or "hidden"))
    else
        ns.Print(string.format("Unknown bar option: %s", argument))
    end
end)
