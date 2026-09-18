local addonName, ns = ...

local Bar = {}
ns.Bar = Bar

ns.AddDefaults({
    bar = {
        enabled = true,
        height = 24,
        pushUIDown = true,
        locked = true,
        -- name -> { side, order }, written whenever a module is dragged.
        layout = {},
    },
})

ns.RegisterSetting({
    store = "bar",
    key = "pushUIDown",
    type = "checkbox",
    name = "Reserve space at the top",
    tooltip = "Push Blizzard's frames down so the bar does not cover them.",
    onChange = function()
        ns.Bar:Update()
    end,
})

-- Height sits with "reserve space": both are about how much room the bar takes.
ns.RegisterSetting({
    store = "bar",
    key = "height",
    type = "slider",
    name = "Bar height",
    min = 16,
    max = 48,
    onChange = function()
        ns.Bar:Update()
        ns.Bar:RefreshAll()
    end,
})

ns.RegisterSetting({
    store = "bar",
    key = "locked",
    type = "checkbox",
    name = "Lock modules",
    tooltip = "Stop modules being dragged along the bar.",
})

local VALID_SIDES = { LEFT = true, CENTER = true, RIGHT = true }
local EDGE_PADDING = 10
local MODULE_SPACING = 16
local MIN_HEIGHT, MAX_HEIGHT = 16, 48
local DRAG_ALPHA = 0.6
-- Sampled off a Titan Panel screenshot. The bar is not one flat colour: it runs
-- from #3A3028 at the top down to #1D0E09 at the bottom, and it is the gradient
-- that makes it read as a lit surface. Averaging the two into the midpoint
-- (#372F21) gives a flat brown slab that looks nothing like the original.
local BACKGROUND_TOP = { r = 0.227, g = 0.188, b = 0.157 }
local BACKGROUND_BOTTOM = { r = 0.114, g = 0.055, b = 0.035 }
-- The gold edge along the bottom, from the same screenshot: #715C3C. It is what
-- separates the bar from the game world underneath it.
local BORDER_COLOR = { r = 0.443, g = 0.361, b = 0.235 }
local BORDER_HEIGHT = 2
-- The bar owns the text colour rather than leaving it to each module, so a new
-- module cannot render itself unreadable by leaving GameFontNormal alone.
local TEXT_COLOR = { r = 1, g = 1, b = 1 }

local modules = {}
local modulesByName = {}
local eventMap = {}
local barFrame, dispatcher
local initialized = false
local layoutQueued = false
local applyingInset, insetReapplyQueued, insetHookInstalled = false, false, false
local dragging, dragSide, dragIndex

local function byOrder(a, b)
    if a.order ~= b.order then
        return a.order < b.order
    end
    return a.name < b.name
end

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
        -- Two separate reasons to be absent: the module has nothing to say
        -- (xp at max level), or you turned it off. Either one closes the gap.
        local visible = entry.shown ~= false and not entry.hiddenByUser
        if visible and VALID_SIDES[entry.side] then
            table.insert(bySide[entry.side], entry)
        end
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

--- Turn anchored positions into plain distances from the bar's left edge, so
-- drag targets can be compared against the cursor. Pure.
local function computeCenters(entries, barWidth, options)
    local positions = computeLayout(entries, options)
    local widths = {}
    for _, entry in ipairs(entries) do
        widths[entry.name] = entry.width or 0
    end

    local centers = {}
    for name, position in pairs(positions) do
        local width = widths[name] or 0
        if position.anchor == "LEFT" then
            centers[name] = position.offset + width / 2
        elseif position.anchor == "RIGHT" then
            centers[name] = barWidth + position.offset - width / 2
        else
            centers[name] = barWidth / 2 + position.offset
        end
    end

    return centers
end

Bar.ComputeCenters = computeCenters

--- Which third of the bar the cursor is over. Pure.
local function sideForCursor(cursorX, barWidth)
    if not barWidth or barWidth <= 0 then
        return "CENTER"
    end
    if cursorX < barWidth / 3 then
        return "LEFT"
    end
    if cursorX < barWidth * 2 / 3 then
        return "CENTER"
    end
    return "RIGHT"
end

Bar.SideForCursor = sideForCursor

--- Where in an ordered list of visible modules the cursor wants to insert. Pure.
local function dropIndex(orderedNames, centers, cursorX)
    local index = 1
    for _, name in ipairs(orderedNames) do
        if cursorX > (centers[name] or 0) then
            index = index + 1
        end
    end
    return index
end

Bar.DropIndex = dropIndex

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
-- Saved module order
--------------------------------------------------------------------------------

local function saveLayout()
    if not ns.db then
        return
    end

    local saved = {}
    for _, module in ipairs(modules) do
        saved[module.name] = { side = module.side, order = module.order }
    end
    ns.db.bar.layout = saved
end

local function applySavedLayout()
    local saved = ns.db and ns.db.bar.layout
    if type(saved) ~= "table" then
        return
    end

    for _, module in ipairs(modules) do
        local entry = saved[module.name]
        if type(entry) == "table" and VALID_SIDES[entry.side] and type(entry.order) == "number" then
            module.side = entry.side
            module.order = entry.order
        end
    end
end

Bar.ApplySavedLayout = applySavedLayout

local function resetLayout()
    for _, module in ipairs(modules) do
        module.side = module.defaultSide
        module.order = module.defaultOrder
    end

    if ns.db then
        ns.db.bar.layout = {}
    end

    applyLayout()
end

--- Move a module to a side, inserting it before the visibleIndex-th visible
-- module already there, then renumber that side so the order sticks.
local function moveModule(module, side, visibleIndex)
    local siblings = {}
    for _, other in ipairs(modules) do
        if other ~= module and other.side == side then
            table.insert(siblings, other)
        end
    end
    table.sort(siblings, byOrder)

    -- Translate an index among the visible modules into one in the full list,
    -- so hidden modules keep their relative place. Dropping in front of
    -- everything visible must land in front, even when hidden modules sort
    -- earlier, otherwise the drop lands somewhere the cursor never was.
    local insertAt, lastVisible = nil, nil
    local seen = 0
    for index, other in ipairs(siblings) do
        if other.shown then
            seen = seen + 1
            lastVisible = index
            if seen == visibleIndex then
                insertAt = index
                break
            end
        end
    end

    if not insertAt then
        insertAt = lastVisible and (lastVisible + 1) or 1
    end

    module.side = side
    table.insert(siblings, insertAt, module)

    for index, other in ipairs(siblings) do
        other.order = index * 10
    end

    saveLayout()
end

Bar.MoveModule = moveModule

--------------------------------------------------------------------------------
-- Dragging
--------------------------------------------------------------------------------

local function cursorOffsetInBar()
    if not barFrame or type(GetCursorPosition) ~= "function" then
        return nil
    end

    local scale = barFrame:GetEffectiveScale()
    if not scale or scale == 0 then
        return nil
    end

    local left = barFrame:GetLeft()
    if not left then
        return nil
    end

    return (GetCursorPosition() / scale) - left
end

--- Live reordering: while a module is held, it is moved into the slot the
-- cursor is over, so the bar itself is the drag preview.
function Bar:UpdateDrag()
    if not dragging or not barFrame then
        return
    end

    local cursorX = cursorOffsetInBar()
    if not cursorX then
        return
    end

    local barWidth = barFrame:GetWidth()
    local side = sideForCursor(cursorX, barWidth)
    local centers = computeCenters(modules, barWidth)

    local neighbours = {}
    for _, module in ipairs(modules) do
        if module ~= dragging and module.side == side and module.shown then
            table.insert(neighbours, module)
        end
    end
    table.sort(neighbours, byOrder)

    local names = {}
    for index, module in ipairs(neighbours) do
        names[index] = module.name
    end

    local index = dropIndex(names, centers, cursorX)

    if side ~= dragSide or index ~= dragIndex then
        dragSide, dragIndex = side, index
        moveModule(dragging, side, index)
        applyLayout()
    end
end

function Bar:StartDrag(module)
    if not barFrame or ns.db.bar.locked or dragging then
        return
    end

    dragging = module
    dragSide, dragIndex = nil, nil
    module.frame:SetAlpha(DRAG_ALPHA)
    barFrame:SetScript("OnUpdate", function()
        Bar:UpdateDrag()
    end)

    self:UpdateDrag()
end

function Bar:StopDrag()
    if not dragging then
        return
    end

    dragging.frame:SetAlpha(1)
    dragging = nil
    dragSide, dragIndex = nil, nil

    if barFrame then
        barFrame:SetScript("OnUpdate", nil)
    end

    saveLayout()
    applyLayout()
end

function Bar:IsDragging()
    return dragging ~= nil
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
    frame:RegisterForDrag("LeftButton")
    module.frame = frame

    frame:SetScript("OnDragStart", function()
        Bar:StartDrag(module)
    end)

    frame:SetScript("OnDragStop", function()
        Bar:StopDrag()
    end)

    -- Always wired, even for a module with no OnClick of its own: a module
    -- covers part of the bar, so without this the right-click menu would be
    -- unreachable wherever you happened to click on text.
    frame:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            Bar:OpenMenu(frame)
        elseif module.OnClick then
            module:OnClick(button)
        end
    end)

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

    if module.text and module.text.SetTextColor then
        module.text:SetTextColor(TEXT_COLOR.r, TEXT_COLOR.g, TEXT_COLOR.b)
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

    local order = definition.order or 100

    local module = setmetatable({
        name = name,
        side = side,
        order = order,
        -- Kept so "bar reset" can put everything back where it started.
        defaultSide = side,
        defaultOrder = order,
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

    -- Every module gets a visibility switch without having to ask for one, so
    -- a new module is on the settings panel the moment it is registered.
    ns.AddDefaults({ modules = { [name] = true } })
    ns.RegisterSetting({
        store = "modules",
        key = name,
        type = "checkbox",
        name = "Show " .. (definition.label or name),
        onChange = function()
            Bar:ApplyModuleVisibility()
        end,
    })

    -- Modules registered after login still get built and placed.
    if initialized then
        applySavedLayout()
        createModuleFrame(module)
        queueLayout()
    end

    return module
end

function Bar:GetModule(name)
    return modulesByName[name]
end

--- Read each module's visibility switch out of the database and reflow.
function Bar:ApplyModuleVisibility()
    local stored = ns.db and ns.db.modules
    if not stored then
        return
    end

    for _, module in ipairs(modules) do
        module.hiddenByUser = stored[module.name] == false
    end

    applyLayout()
end

function Bar:RefreshAll()
    for _, module in ipairs(modules) do
        module:Refresh()
    end
end

--- Re-measure every module from its font string.
-- A module takes its width when it sets its text, but the client cannot measure
-- a font string until it has been laid out, so a width taken during login is
-- always 0. Only the bar knows that first measurement happened before the first
-- frame, so the bar re-takes it here: a module that skips work when its text has
-- not changed (the clock does, so a 1 second ticker does not dirty the layout)
-- would otherwise never measure itself again.
local function remeasureModules()
    for _, module in ipairs(modules) do
        local text = module.text
        if text and text.GetStringWidth then
            module:SetWidth(text:GetStringWidth())
        end
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

    applyingInset = true
    local ok, err = pcall(function()
        UIParent:ClearAllPoints()
        UIParent:SetPoint("TOPLEFT", nil, "TOPLEFT", 0, -inset)
        UIParent:SetPoint("BOTTOMRIGHT", nil, "BOTTOMRIGHT", 0, 0)
    end)
    applyingInset = false

    -- Kept for "bar debug": whether the call threw, and what it actually
    -- achieved. Reading the edge straight back distinguishes a call that failed
    -- from one that succeeded and was undone again afterwards.
    Bar.lastInset = {
        wanted = inset,
        ok = ok,
        err = ok and nil or tostring(err),
        topAfter = UIParent.GetTop and UIParent:GetTop() or nil,
    }

    if not ok then
        ns.Print("Could not reserve space at the top of the screen. Use /fp bar push to turn this off.")
    end

    return ok
end

Bar.ApplyUIParentInset = applyUIParentInset

--- Keep the inset in force.
-- Blizzard re-anchors UIParent back to the full screen after login: the call
-- above succeeds and UIParent really is inset, then it is back at full height by
-- the time anything looks at it. Rather than guess which event that is, watch
-- UIParent for anyone else re-anchoring it and put the inset back afterwards.
-- Our own SetPoint calls are ignored, so this cannot feed itself.
local function installInsetHook()
    if insetHookInstalled or not UIParent or not hooksecurefunc then
        return
    end
    insetHookInstalled = true

    local function reapply()
        if applyingInset or insetReapplyQueued then
            return
        end
        insetReapplyQueued = true
        C_Timer.After(0, function()
            insetReapplyQueued = false
            applyUIParentInset()
        end)
    end

    hooksecurefunc(UIParent, "SetPoint", reapply)
    hooksecurefunc(UIParent, "SetAllPoints", reapply)
end

local function anchorBar()
    if not barFrame then
        return
    end

    local config = ns.db.bar
    barFrame:ClearAllPoints()

    -- Always the top of the screen, never UIParent's top edge. UIParent's top is
    -- wherever applyUIParentInset last managed to put it, and Blizzard re-anchors
    -- UIParent at times of its own choosing; a bar anchored above that edge ends
    -- up off the top of the screen, invisible, the moment the inset is not in
    -- force. WorldFrame always covers the screen, so pushUIDown now only decides
    -- whether Blizzard's frames move out from under the bar, not whether the bar
    -- can be seen at all.
    barFrame:SetPoint("TOPLEFT", WorldFrame, "TOPLEFT", 0, 0)
    barFrame:SetPoint("TOPRIGHT", WorldFrame, "TOPRIGHT", 0, 0)

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
-- Right-click menu
--------------------------------------------------------------------------------

--- Open the bar's context menu over a frame.
-- Actions only. Toggles all live on the settings panel: a checkbox here would
-- be a second place to keep them in step, and toggling one that re-anchors
-- UIParent slid the open menu out from under the cursor.
function Bar:OpenMenu(owner)
    if dragging or not MenuUtil then
        return
    end

    MenuUtil.CreateContextMenu(owner or barFrame, function(_, root)
        root:CreateTitle("ForeverPanel")
        root:CreateButton("Settings...", function()
            ns.OpenSettings()
        end)
        root:CreateButton("Reset module order", function()
            resetLayout()
            ns.Print("Module order reset.")
        end)
    end)
end

--------------------------------------------------------------------------------
-- Setup
--------------------------------------------------------------------------------

--- Paint the bar's backdrop as a vertical gradient.
-- SetGradient takes colour objects from 10.0 onwards and raw numbers before
-- that, and the Classic clients did not all move at once, so a client that
-- wants the old form gets the dark end as a flat fill rather than an error.
local function paintBackground(texture)
    local ok = pcall(function()
        texture:SetColorTexture(1, 1, 1, 1)
        texture:SetGradient(
            "VERTICAL",
            CreateColor(BACKGROUND_BOTTOM.r, BACKGROUND_BOTTOM.g, BACKGROUND_BOTTOM.b, 1),
            CreateColor(BACKGROUND_TOP.r, BACKGROUND_TOP.g, BACKGROUND_TOP.b, 1)
        )
    end)

    if not ok then
        texture:SetColorTexture(BACKGROUND_BOTTOM.r, BACKGROUND_BOTTOM.g, BACKGROUND_BOTTOM.b, 1)
    end

    return ok
end

Bar.PaintBackground = paintBackground

function Bar:Initialize()
    if initialized then
        return
    end
    initialized = true

    barFrame = CreateFrame("Frame", "ForeverBar", UIParent)
    barFrame:SetFrameStrata("MEDIUM")
    barFrame:EnableMouse(true)
    barFrame:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then
            Bar:OpenMenu(self)
        end
    end)

    local background = barFrame:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    paintBackground(background)
    barFrame.background = background

    local border = barFrame:CreateTexture(nil, "BORDER")
    border:SetPoint("BOTTOMLEFT")
    border:SetPoint("BOTTOMRIGHT")
    border:SetHeight(BORDER_HEIGHT)
    border:SetColorTexture(BORDER_COLOR.r, BORDER_COLOR.g, BORDER_COLOR.b, 1)
    barFrame.border = border

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

    applySavedLayout()
    installInsetHook()

    for _, module in ipairs(modules) do
        module.hiddenByUser = ns.db.modules[module.name] == false
    end

    for _, module in ipairs(modules) do
        createModuleFrame(module)
    end

    self:Update()

    -- A font string cannot be measured until the client has laid it out, which
    -- does not happen until the frame after the text is set. Everything built
    -- above therefore measured 0 wide. Re-measure once the first frame has been
    -- drawn, otherwise the modules keep those zero widths and sit stacked on
    -- top of each other until some unrelated event happens to resize them.
    C_Timer.After(0, function()
        Bar:RefreshAll()
        remeasureModules()
        applyLayout()
    end)
end

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------

ns.RegisterCommand("bar", "Toggle the bar. Also: bar height <16-48>, bar push, bar lock, bar reset, bar debug", function(rest)
    local argument, value = (rest or ""):match("^(%S*)%s*(.-)$")
    argument = argument:lower()
    local config = ns.db.bar

    if argument == "height" then
        local height = tonumber(value)
        if not height then
            ns.Print(string.format("Bar height is %d. Usage: /fp bar height <%d-%d>", config.height, MIN_HEIGHT, MAX_HEIGHT))
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
    elseif argument == "lock" then
        config.locked = not config.locked
        ns.Print(string.format(
            "Bar modules are %s.",
            config.locked and "locked in place" or "draggable"
        ))
    elseif argument == "reset" then
        resetLayout()
        ns.Print("Module order reset.")
    elseif argument == "debug" then
        local function edge(frame, method)
            if not frame or not frame[method] then
                return "?"
            end
            local value = frame[method](frame)
            return value and string.format("%.0f", value) or "nil"
        end

        ns.Print(string.format(
            "config: enabled=%s push=%s height=%d",
            tostring(config.enabled), tostring(config.pushUIDown), config.height
        ))
        ns.Print(string.format(
            "UIParent: top=%s bottom=%s height=%s",
            edge(UIParent, "GetTop"), edge(UIParent, "GetBottom"), edge(UIParent, "GetHeight")
        ))
        ns.Print(string.format(
            "bar: shown=%s top=%s bottom=%s width=%s alpha=%s",
            barFrame and tostring(barFrame:IsShown()) or "no frame",
            edge(barFrame, "GetTop"), edge(barFrame, "GetBottom"),
            edge(barFrame, "GetWidth"), edge(barFrame, "GetAlpha")
        ))
        ns.Print(string.format("screen height: %s", edge(WorldFrame, "GetHeight")))

        local last = Bar.lastInset
        if last then
            ns.Print(string.format(
                "inset: wanted=%d call=%s topAfter=%s%s",
                last.wanted,
                last.ok and "ok" or "threw",
                last.topAfter and string.format("%.0f", last.topAfter) or "nil",
                last.err and (" err=" .. last.err) or ""
            ))
        end

        for _, module in ipairs(modules) do
            ns.Print(string.format(
                "  %s: side=%s order=%d width=%d shown=%s frameWidth=%s left=%s",
                module.name, module.side, module.order or -1, module.width or -1,
                tostring(module.shown),
                edge(module.frame, "GetWidth"), edge(module.frame, "GetLeft")
            ))
        end

        -- Is the saved layout coming back at all, and does it reach the modules?
        ns.Print(string.format(
            "db: launches=%s sameTable=%s",
            tostring(ns.db.launches), tostring(ns.db == ForeverPanelDB)
        ))

        local layout = ns.db.bar.layout
        if type(layout) ~= "table" then
            ns.Print(string.format("saved layout: %s (not a table)", type(layout)))
        else
            local empty = true
            for name, entry in pairs(layout) do
                empty = false
                ns.Print(string.format(
                    "  saved %s: side=%s order=%s",
                    name, tostring(entry and entry.side), tostring(entry and entry.order)
                ))
            end
            if empty then
                ns.Print("saved layout: empty")
            end
        end
    elseif argument == "" then
        config.enabled = not config.enabled
        Bar:Update()
        ns.Print(string.format("Top bar %s.", config.enabled and "shown" or "hidden"))
    else
        ns.Print(string.format("Unknown bar option: %s", argument))
    end
end)
