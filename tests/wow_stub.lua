-- A minimal stand-in for the WoW API, enough to load the addon outside the
-- game. Widgets record what was done to them so tests can assert on it.

local stub = {}

local function makeWidget(kind, parent)
    local widget = {
        kind = kind,
        parent = parent,
        points = {},
        scripts = {},
        registeredEvents = {},
        children = {},
        width = 0,
        height = 0,
        shown = true,
        text = "",
        alpha = 1,
        metricsReady = false,
        left = 0,
        scale = 1,
    }

    function widget:SetPoint(...)
        table.insert(self.points, { ... })
    end

    function widget:ClearAllPoints()
        self.points = {}
    end

    function widget:SetAllPoints() end

    function widget:GetPoint(index)
        local point = self.points[index or 1]
        if point then
            return table.unpack(point)
        end
    end

    function widget:SetWidth(value)
        self.width = value
    end

    function widget:GetWidth()
        return self.width
    end

    function widget:SetHeight(value)
        self.height = value
    end

    function widget:GetHeight()
        return self.height
    end

    function widget:SetSize(w, h)
        self.width, self.height = w, h
    end

    -- Showing and hiding fire their scripts, and only on a real transition,
    -- the way the client does.
    function widget:Show()
        if self.shown then
            return
        end
        self.shown = true
        local handler = self.scripts.OnShow
        if handler then
            handler(self)
        end
    end

    function widget:Hide()
        if not self.shown then
            return
        end
        self.shown = false
        local handler = self.scripts.OnHide
        if handler then
            handler(self)
        end
    end

    function widget:SetShown(value)
        if value then
            self:Show()
        else
            self:Hide()
        end
    end

    function widget:IsShown()
        return self.shown
    end

    function widget:SetScript(name, fn)
        self.scripts[name] = fn
    end

    function widget:GetScript(name)
        return self.scripts[name]
    end

    function widget:HookScript(name, fn)
        local existing = self.scripts[name]
        self.scripts[name] = function(...)
            if existing then
                existing(...)
            end
            fn(...)
        end
    end

    function widget:RegisterEvent(event)
        self.registeredEvents[event] = true
    end

    function widget:UnregisterEvent(event)
        self.registeredEvents[event] = nil
    end

    function widget:UnregisterAllEvents()
        self.registeredEvents = {}
    end

    function widget:RegisterForClicks() end
    function widget:RegisterForDrag() end
    function widget:EnableMouse() end
    function widget:SetFrameStrata() end
    function widget:SetFrameLevel() end

    function widget:SetAlpha(value)
        self.alpha = value
    end

    function widget:GetAlpha()
        return self.alpha
    end

    function widget:GetLeft()
        return self.left
    end

    function widget:GetEffectiveScale()
        return self.scale
    end
    function widget:SetChecked(value)
        self.checked = value and true or false
    end

    function widget:GetChecked()
        return self.checked
    end

    function widget:SetValue(value)
        self.value = value
    end

    function widget:GetValue()
        return self.value
    end

    function widget:SetMinMaxValues(low, high)
        self.minValue, self.maxValue = low, high
    end

    function widget:SetValueStep() end
    function widget:SetObeyStepOnDrag() end

    function widget:SetTextColor(r, g, b, a)
        self.textColor = { r, g, b, a or 1 }
    end

    function widget:GetTextColor()
        local color = self.textColor
        if not color then
            return nil
        end
        return color[1], color[2], color[3], color[4]
    end

    function widget:SetAutoFocus(value)
        self.autoFocus = value and true or false
    end

    function widget:ClearFocus()
        self.focusCleared = true
    end
    function widget:EnableKeyboard(value)
        self.keyboardEnabled = value and true or false
    end

    function widget:SetPropagateKeyboardInput(value)
        self.propagateKeys = value and true or false
    end

    function widget:SetJustifyH() end
    function widget:SetColorTexture(r, g, b, a)
        self.colorTexture = { r, g, b, a }
        self.gradient = nil
    end

    function widget:SetGradient(orientation, from, to)
        self.gradient = { orientation = orientation, from = from, to = to }
    end
    function widget:SetTexture() end
    function widget:SetFont(file, size, flags)
        self.font = { file = file, size = size, flags = flags or "" }
    end

    function widget:SetParent(value)
        self.parent = value
    end

    function widget:GetParent()
        return self.parent
    end

    function widget:SetText(value)
        value = value or ""
        if value ~= self.text then
            self.text = value
            -- The real client cannot measure text until it has been laid out,
            -- which happens on the next frame, not in this call.
            self.metricsReady = false
        end
    end

    function widget:GetText()
        return self.text
    end

    function widget:GetFont()
        local font = self.font
        if font then
            return font.file, font.size, font.flags
        end
        return "Fonts\\FRIZQT__.TTF", 12, ""
    end

    -- Deterministic fake metrics: 6 units per rendered character, and each
    -- inline texture escape counts as one icon rather than its markup length.
    -- Returns 0 until the text has been through a render pass, like the client.
    function widget:GetStringWidth()
        if not self.metricsReady then
            return 0
        end

        local text = tostring(self.text)

        local icons = 0
        for _ in text:gmatch("|T.-|t") do
            icons = icons + 1
        end

        local rendered = text:gsub("|T.-|t", "")
        return #rendered * 6 + icons * 12
    end

    function widget:CreateTexture()
        local texture = makeWidget("Texture", self)
        table.insert(self.children, texture)
        return texture
    end

    function widget:CreateFontString()
        local fontString = makeWidget("FontString", self)
        table.insert(self.children, fontString)
        return fontString
    end

    -- Test helper: drive this widget's OnEvent handler.
    function widget:Fire(event, ...)
        local handler = self.scripts.OnEvent
        if handler then
            handler(self, event, ...)
        end
    end

    return widget
end

stub.makeWidget = makeWidget

function stub.newEnv()
    local env = setmetatable({}, { __index = _G })

    env.__frames = {}
    env.__timers = {}
    env.__tickers = {}

    env.UIParent = makeWidget("Frame")
    env.WorldFrame = makeWidget("Frame")
    env.TimeManagerClockButton = makeWidget("Button")
    -- The gryphons, nested exactly as the live client reports them:
    -- MainActionBar.EndCaps.LeftEndCap
    env.MainActionBar = makeWidget("Frame")
    env.MainActionBar.EndCaps = makeWidget("Frame")
    env.MainActionBar.EndCaps.LeftEndCap = makeWidget("Frame")
    env.MainActionBar.EndCaps.RightEndCap = makeWidget("Frame")
    -- The font object every unit frame's health and mana text inherits from.
    env.TextStatusBarText = makeWidget("FontString")
    -- Both start closed, as they do in game, so Show() is a real transition
    -- and fires OnShow.
    env.SettingsPanel = makeWidget("Frame")
    env.SettingsPanel.shown = false
    env.GameMenuFrame = makeWidget("Frame")
    env.GameMenuFrame.shown = false
    env.SlashCmdList = {}

    env.MenuResponse = { Open = 1, Close = 2, CloseAll = 3, Refresh = 4 }

    function env.HideUIPanel(frame)
        if frame and frame.Hide then
            frame:Hide()
        end
    end

    -- In the client the addon environment *is* the global table, so code that
    -- reaches a frame by name through _G finds the same frames as code that
    -- names them directly.
    env._G = env

    env.__overrideBindings = {}
    env.__chatOpenedWith = nil
    env.__inCombat = false
    env.modifiers = {}

    function env.InCombatLockdown()
        return env.__inCombat
    end

    function env.SetOverrideBindingClick(owner, priority, key, buttonName)
        env.__overrideBindings[key] = buttonName
    end

    function env.ClearOverrideBindings()
        env.__overrideBindings = {}
    end

    function env.ChatFrame_OpenChat(text)
        env.__chatOpenedWith = text
    end

    function env.IsControlKeyDown()
        return env.modifiers.ctrl and true or false
    end

    function env.IsShiftKeyDown()
        return env.modifiers.shift and true or false
    end

    function env.IsAltKeyDown()
        return env.modifiers.alt and true or false
    end

    env.__cvars = {}

    function env.SetCVar(name, value)
        env.__cvars[name] = tostring(value)
    end

    function env.GetCVar(name)
        return env.__cvars[name]
    end

    function env.CreateFrame(kind, name, parent)
        local frame = makeWidget(kind or "Frame", parent)
        frame.frameName = name
        table.insert(env.__frames, frame)
        if name then
            env[name] = frame
        end
        return frame
    end

    env.cursorX, env.cursorY = 0, 0
    function env.GetCursorPosition()
        return env.cursorX, env.cursorY
    end

    env.money = 0
    function env.GetMoney()
        return env.money
    end

    env.xp, env.xpMax, env.xpDisabled = 0, 0, false

    function env.UnitXP()
        return env.xp
    end

    function env.UnitXPMax()
        return env.xpMax
    end

    function env.IsXPUserDisabled()
        return env.xpDisabled
    end

    function env.UnitLevel()
        return 60
    end

    function env.BreakUpLargeNumbers(value)
        local digits = tostring(math.floor(value))
        local grouped = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse()
        return (grouped:gsub("^,", ""))
    end

    -- Records what a context menu was built from, so tests can read the entries
    -- back and invoke them the way a click would.
    local function makeMenuRoot()
        local root = { entries = {} }

        local function add(entry)
            table.insert(root.entries, entry)
            return entry
        end

        function root:CreateTitle(text)
            return add({ kind = "title", text = text })
        end

        function root:CreateButton(text, callback)
            return add({ kind = "button", text = text, callback = callback })
        end

        function root:CreateCheckbox(text, isSelected, setSelected)
            return add({
                kind = "checkbox",
                text = text,
                isSelected = isSelected,
                setSelected = setSelected,
            })
        end

        function root:CreateDivider()
            return add({ kind = "divider" })
        end

        --- Find an entry by its label.
        function root:Find(text)
            for _, entry in ipairs(self.entries) do
                if entry.text == text then
                    return entry
                end
            end
        end

        return root
    end

    env.MenuUtil = {
        CreateContextMenu = function(owner, generator)
            local root = makeMenuRoot()
            generator(owner, root)
            env.__menu = root
            env.__menuOwner = owner
            return root
        end,
    }

    env.Settings = {
        RegisterCanvasLayoutCategory = function(frame, name)
            return {
                name = name,
                frame = frame,
                GetID = function()
                    return "category-id"
                end,
            }
        end,
        RegisterAddOnCategory = function(category)
            env.__settingsCategory = category
        end,
        OpenToCategory = function(id)
            env.__openedCategory = id
        end,
    }

    -- Free slots per bag, and the bag's type: 0 is general purpose, anything
    -- else only takes particular items.
    env.NUM_BAG_SLOTS = 4
    env.bagSlots = {
        [0] = { free = 4, total = 16, kind = 0 },
        [1] = { free = 6, total = 16, kind = 0 },
        [2] = { free = 2, total = 8, kind = 0 },
        [3] = { free = 0, total = 0, kind = 0 },
        [4] = { free = 0, total = 0, kind = 0 },
    }

    env.C_Container = {
        GetContainerNumFreeSlots = function(bag)
            local entry = env.bagSlots[bag]
            if not entry then
                return nil
            end
            return entry.free, entry.kind
        end,
        GetContainerNumSlots = function(bag)
            local entry = env.bagSlots[bag]
            return entry and entry.total or 0
        end,
    }

    function env.OpenAllBags()
        env.__bagsOpened = true
    end

    env.C_AddOns = {
        GetAddOnMetadata = function(_, field)
            return field == "Version" and "9.9.9" or nil
        end,
    }

    function env.CreateColor(r, g, b, a)
        return { r = r, g = g, b = b, a = a }
    end

    env.date = os.date

    env.C_Timer = {
        After = function(_, fn)
            table.insert(env.__timers, fn)
        end,
        NewTicker = function(interval, fn)
            local ticker = { interval = interval, fn = fn, Cancel = function() end }
            table.insert(env.__tickers, ticker)
            return ticker
        end,
    }

    function env.hooksecurefunc(target, name, post)
        local original = target[name]
        target[name] = function(...)
            local result = original(...)
            post(...)
            return result
        end
    end

    -- Test helper: simulate the render pass that makes text measurable.
    function env.__render()
        local seen = {}

        local function mark(widget)
            if seen[widget] then
                return
            end
            seen[widget] = true
            widget.metricsReady = true
            for _, child in ipairs(widget.children) do
                mark(child)
            end
        end

        mark(env.UIParent)
        for _, frame in ipairs(env.__frames) do
            mark(frame)
        end
    end

    -- Test helpers.
    -- A timer queued during one frame does not fire until the next one, and the
    -- client draws in between, so anything queued can rely on text being
    -- measurable by the time it runs.
    function env.__runTimers()
        local pending = env.__timers
        env.__timers = {}
        if #pending == 0 then
            return
        end

        env.__render()
        for _, fn in ipairs(pending) do
            fn()
        end
    end

    function env.__tick()
        for _, ticker in ipairs(env.__tickers) do
            ticker.fn()
        end
        env.__runTimers()
    end

    return env
end

return stub
