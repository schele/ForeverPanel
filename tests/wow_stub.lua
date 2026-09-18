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

    function widget:Show()
        self.shown = true
    end

    function widget:Hide()
        self.shown = false
    end

    function widget:SetShown(value)
        self.shown = value and true or false
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

    function widget:SetJustifyH() end
    function widget:SetColorTexture(r, g, b, a)
        self.colorTexture = { r, g, b, a }
        self.gradient = nil
    end

    function widget:SetGradient(orientation, from, to)
        self.gradient = { orientation = orientation, from = from, to = to }
    end
    function widget:SetTexture() end
    function widget:SetFont() end

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
    env.SlashCmdList = {}

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
