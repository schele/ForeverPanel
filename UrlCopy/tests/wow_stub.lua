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
        highlighted = false,
        focused = false,
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

    function widget:SetWidth(value) self.width = value end
    function widget:GetWidth() return self.width end
    function widget:SetHeight(value) self.height = value end
    function widget:GetHeight() return self.height end
    function widget:SetSize(w, h) self.width, self.height = w, h end

    -- Showing and hiding fire their scripts, and only on a real transition,
    -- the way the client does.
    function widget:Show()
        if self.shown then return end
        self.shown = true
        local handler = self.scripts.OnShow
        if handler then handler(self) end
    end

    function widget:Hide()
        if not self.shown then return end
        self.shown = false
        local handler = self.scripts.OnHide
        if handler then handler(self) end
    end

    function widget:SetShown(value)
        if value then self:Show() else self:Hide() end
    end

    function widget:IsShown() return self.shown end

    function widget:SetScript(name, fn) self.scripts[name] = fn end
    function widget:GetScript(name) return self.scripts[name] end

    function widget:HookScript(name, fn)
        local existing = self.scripts[name]
        self.scripts[name] = function(...)
            if existing then existing(...) end
            fn(...)
        end
    end

    function widget:RegisterEvent(event) self.registeredEvents[event] = true end
    function widget:UnregisterEvent(event) self.registeredEvents[event] = nil end
    function widget:UnregisterAllEvents() self.registeredEvents = {} end

    function widget:RegisterForClicks() end
    function widget:EnableMouse() end
    function widget:SetFrameStrata() end
    function widget:SetFrameLevel() end
    function widget:SetJustifyH() end
    function widget:SetMaxLetters() end
    function widget:SetAutoFocus(value) self.autoFocus = value and true or false end

    function widget:SetChecked(value) self.checked = value and true or false end
    function widget:GetChecked() return self.checked end

    function widget:SetValue(value)
        self.value = value
        local handler = self.scripts.OnValueChanged
        if handler then handler(self, value) end
    end

    function widget:GetValue() return self.value end
    function widget:SetMinMaxValues(low, high) self.minValue, self.maxValue = low, high end
    function widget:SetValueStep() end
    function widget:SetObeyStepOnDrag() end

    function widget:SetText(value)
        self.text = value or ""
        local handler = self.scripts.OnTextChanged
        if handler then handler(self) end
    end

    function widget:GetText() return self.text end
    function widget:GetName() return self.frameName end

    -- The three calls that make a copy box a copy box.
    function widget:HighlightText() self.highlighted = true end
    function widget:SetFocus() self.focused = true end
    function widget:ClearFocus() self.focused = false end

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

    function widget:GetParent() return self.parent end
    function widget:SetParent(value) self.parent = value end

    -- Test helper: drive this widget's OnEvent handler.
    function widget:Fire(event, ...)
        local handler = self.scripts.OnEvent
        if handler then handler(self, event, ...) end
    end

    return widget
end

stub.makeWidget = makeWidget

function stub.newEnv()
    local env = setmetatable({}, { __index = _G })

    env.__frames = {}
    env.__printed = {}

    -- In the client the addon environment *is* the global table, so code that
    -- reaches a frame by name through _G finds the same frames as code that
    -- names them directly.
    env._G = env

    env.UIParent = makeWidget("Frame")
    env.SlashCmdList = {}
    env.OKAY = "Okay"

    function env.print(...)
        local pieces = {}
        for index = 1, select("#", ...) do
            pieces[index] = tostring((select(index, ...)))
        end
        table.insert(env.__printed, table.concat(pieces, " "))
    end

    function env.CreateFrame(kind, name, parent)
        local frame = makeWidget(kind or "Frame", parent)
        frame.frameName = name
        table.insert(env.__frames, frame)
        if name then env[name] = frame end
        return frame
    end

    -- Chat -------------------------------------------------------------
    -- Filters are stored per event and run in registration order, and the
    -- return contract matches ChatFrame.lua: a truthy first value suppresses
    -- the message, and a second value replaces it.
    env.ChatFrame1 = makeWidget("Frame")
    env.__filters = {}

    function env.ChatFrame_AddMessageEventFilter(event, filter)
        env.__filters[event] = env.__filters[event] or {}
        table.insert(env.__filters[event], filter)
    end

    --- Test helper: push a message through the filters for an event and
    -- return what chat would show, or nil if it was suppressed.
    function env.__say(event, message, author)
        local filters = env.__filters[event]
        if not filters then
            return message
        end

        for _, filter in ipairs(filters) do
            local suppress, newMessage = filter(env.ChatFrame1, event, message, author)
            if suppress then
                return nil
            end
            if newMessage then
                message = newMessage
            end
        end

        return message
    end

    -- The client's own handler. Unknown link types fall through it silently,
    -- which is exactly what lets an addon add one.
    env.__itemRefs = {}
    function env.SetItemRef(link, text, button)
        table.insert(env.__itemRefs, { link = link, text = text, button = button })
    end

    -- Static popups ----------------------------------------------------
    env.StaticPopupDialogs = {}
    env.__shownPopup = nil

    function env.StaticPopup_Show(which)
        local definition = env.StaticPopupDialogs[which]
        if not definition then
            return nil
        end

        local dialog = makeWidget("Frame")
        dialog.frameName = "StaticPopup1"
        dialog.which = which
        dialog.editBox = makeWidget("EditBox", dialog)

        -- The client wires these template scripts onto the edit box.
        if definition.EditBoxOnTextChanged then
            dialog.editBox:SetScript("OnTextChanged", function(box)
                definition.EditBoxOnTextChanged(box, dialog.data)
            end)
        end
        if definition.EditBoxOnEnterPressed then
            dialog.editBox:SetScript("OnEnterPressed", function(box)
                definition.EditBoxOnEnterPressed(box, dialog.data)
            end)
        end
        if definition.EditBoxOnEscapePressed then
            dialog.editBox:SetScript("OnEscapePressed", function(box)
                definition.EditBoxOnEscapePressed(box, dialog.data)
            end)
        end

        env.__shownPopup = dialog
        if definition.OnShow then
            definition.OnShow(dialog)
        end

        return dialog
    end

    function env.StaticPopup_Hide(which)
        if env.__shownPopup and env.__shownPopup.which == which then
            env.__shownPopup.hidden = true
        end
    end

    -- Settings ---------------------------------------------------------
    env.SettingsPanel = makeWidget("Frame")
    env.SettingsPanel.shown = false
    env.GameMenuFrame = makeWidget("Frame")
    env.GameMenuFrame.shown = false

    function env.HideUIPanel(frame)
        if frame and frame.Hide then frame:Hide() end
    end

    env.Settings = {
        RegisterCanvasLayoutCategory = function(frame, name)
            return {
                name = name,
                frame = frame,
                GetID = function() return "category-id" end,
            }
        end,
        RegisterAddOnCategory = function(category)
            env.__settingsCategory = category
        end,
        OpenToCategory = function(id)
            env.__openedCategory = id
        end,
    }

    env.C_AddOns = {
        GetAddOnMetadata = function(_, field)
            return field == "Version" and "9.9.9" or nil
        end,
    }

    env.C_Timer = {
        After = function(_, fn) fn() end,
    }

    -- Both forms: hooksecurefunc(table, name, post) and the global-name form
    -- hooksecurefunc(name, post), which is how SetItemRef is hooked.
    function env.hooksecurefunc(target, name, post)
        if type(target) == "string" then
            target, name, post = env, target, name
        end

        local original = target[name]
        target[name] = function(...)
            local result = original(...)
            post(...)
            return result
        end
    end

    return env
end

return stub
