local helpers = require("helpers")

local function loggedIn()
    local ns, env = helpers.loadAddon()
    helpers.login(ns, env)

    -- The panel builds itself the first time it is opened, so say so rather
    -- than expecting controls to exist from login.
    ns.Settings.EnsureBuilt()

    return ns, env
end

--- Right-click the bar itself.
local function rightClickBar(env)
    env.ForeverBar.scripts.OnMouseUp(env.ForeverBar, "RightButton")
    return env.__menu
end

describe("the settings registry", function()
    it("collects a declaration from each file that owns config", function()
        local ns = helpers.loadAddon()

        local byKey = {}
        for _, setting in ipairs(ns.settings) do
            byKey[setting.store .. "." .. setting.key] = setting
        end

        -- Each file declares its own, the way AddDefaults and RegisterCommand
        -- already work, so adding a module needs no edit to Settings.lua.
        assertTrue(byKey["bar.pushUIDown"] ~= nil, "the bar declares pushUIDown")
        assertTrue(byKey["bar.height"] ~= nil, "the bar declares height")
        assertTrue(byKey["bar.locked"] ~= nil, "the bar declares locked")
        assertTrue(byKey["ui.hideEndCaps"] ~= nil, "the tweaks declare hideEndCaps")

        -- XP's direction stays off the panel: clicking the block toggles it.
        assertTrue(byKey["xp.countDown"] == nil, "xp direction is a click")
    end)

    it("rejects a declaration with no backing default", function()
        local ns = helpers.loadAddon()

        assertErrors(function()
            ns.RegisterSetting({ store = "bar", key = "nope", type = "checkbox", name = "Nope" })
        end)
    end)

    it("reads and writes the value through the database", function()
        local ns, env = loggedIn()

        local setting
        for _, candidate in ipairs(ns.settings) do
            if candidate.key == "hideEndCaps" then
                setting = candidate
            end
        end

        assertTrue(ns.SettingValue(setting), "starts on")
        ns.SetSettingValue(setting, false)
        assertFalse(ns.db.ui.hideEndCaps, "written through to the database")
        assertFalse(ns.SettingValue(setting), "and reads back")
    end)

    it("runs the setting's onChange when the value changes", function()
        local ns, env = loggedIn()

        local ran = false
        local setting = ns.RegisterSetting({
            store = "bar",
            key = "height",
            type = "slider",
            name = "Test height",
            min = 16,
            max = 48,
            onChange = function()
                ran = true
            end,
        })

        ns.SetSettingValue(setting, 32)
        assertTrue(ran, "onChange fired")
        assertEqual(32, ns.db.bar.height)
    end)
end)

describe("the right-click menu", function()
    it("opens from the bar itself", function()
        local ns, env = loggedIn()

        local menu = rightClickBar(env)
        assertTrue(menu ~= nil, "a context menu was built")
        assertEqual(env.ForeverBar, env.__menuOwner)
        assertTrue(menu:Find("ForeverPanel") ~= nil, "titled")
    end)

    it("opens from a module too, without firing its click handler", function()
        local ns, env = loggedIn()

        local module = ns.Bar:GetModule("clock")
        local before = ns.db.clock.use24Hour

        module.frame.scripts.OnClick(module.frame, "RightButton")

        assertTrue(env.__menu ~= nil, "the menu opened over the module")
        assertEqual(before, ns.db.clock.use24Hour, "the clock did not also toggle")
    end)

    it("still passes a left click to the module", function()
        local ns, env = loggedIn()

        local module = ns.Bar:GetModule("clock")
        local before = ns.db.clock.use24Hour

        module.frame.scripts.OnClick(module.frame, "LeftButton")

        assertTrue(before ~= ns.db.clock.use24Hour, "the clock toggled")
    end)

    it("offers a settings entry that opens the panel", function()
        local ns, env = loggedIn()

        local entry = rightClickBar(env):Find("Settings...")
        assertTrue(entry ~= nil, "the menu has a settings entry")

        entry.callback()
        assertEqual("category-id", env.__openedCategory, "it opened our category")
    end)

    -- Toggles belong on the panel. One that re-anchors UIParent slid the open
    -- menu out from under the cursor, and any of them would be a second place
    -- to keep in step with the panel.
    it("carries actions only, no toggles", function()
        local ns, env = loggedIn()

        for _, entry in ipairs(rightClickBar(env).entries) do
            assertTrue(entry.kind ~= "checkbox", "no checkbox in the menu")
        end
    end)

    it("resets the module order from the menu", function()
        local ns, env = loggedIn()

        ns.Bar:GetModule("money").side = "CENTER"
        rightClickBar(env):Find("Reset module order").callback()

        assertEqual("LEFT", ns.Bar:GetModule("money").side, "back to the default")
    end)

    it("does not open while the bar is being dragged", function()
        local ns, env = loggedIn()
        ns.db.bar.locked = false

        local module = ns.Bar:GetModule("money")
        module.frame.scripts.OnDragStart(module.frame)
        env.__menu = nil

        rightClickBar(env)
        assertTrue(env.__menu == nil, "no menu mid-drag")
    end)
end)

describe("the settings panel", function()
    it("registers a category with the game's options", function()
        local ns, env = loggedIn()

        assertTrue(env.__settingsCategory ~= nil, "a category was registered")
        assertEqual("ForeverPanel", env.__settingsCategory.name)
    end)

    it("keeps bar height with the setting it belongs to", function()
        local ns, env = loggedIn()

        local order = {}
        for _, control in ipairs(ns.Settings.controls) do
            table.insert(order, control.setting.key)
        end

        assertEqual("pushUIDown", order[1])
        assertEqual("height", order[2], "height sits under reserve space")
        assertEqual("locked", order[3])
    end)

    -- Built parentless and shown, the canvas and its eight edit boxes sat live
    -- on screen from login, outside any parent, until opening the category
    -- finally put them somewhere. Nothing of ours should be live until asked.
    it("builds nothing at all until the category is opened", function()
        local ns, env = helpers.loadAddon()
        helpers.login(ns, env)

        assertTrue(ns.Settings.panel ~= nil, "the canvas exists")
        assertFalse(ns.Settings.panel:IsShown(), "but is not shown at login")
        assertEqual(env.UIParent, ns.Settings.panel.parent, "and is parented")
        assertEqual(0, #ns.Settings.controls, "no widgets exist yet")

        ns.Settings.EnsureBuilt()
        assertTrue(#ns.Settings.controls > 0, "built on demand")
    end)

    it("shows the version it is running, read from the .toc", function()
        local ns, env = loggedIn()

        -- Read from the addon's own metadata rather than a constant in the
        -- source, which would drift from the .toc the moment one is bumped.
        assertEqual("Version 9.9.9", ns.Settings.version:GetText())
    end)

    it("builds once, however many times it is opened", function()
        local ns, env = loggedIn()
        local first = #ns.Settings.controls

        ns.Settings.EnsureBuilt()
        ns.Settings.panel.scripts.OnShow(ns.Settings.panel)

        assertEqual(first, #ns.Settings.controls, "no duplicate controls")
    end)

    it("draws a divider between the groups, and only between them", function()
        local ns, env = loggedIn()

        assertEqual(1, #ns.Settings.dividers, "one divider for two groups")
    end)

    it("puts the grouped settings below the ungrouped ones", function()
        local ns, env = loggedIn()

        local lastMain, firstGrouped
        for index, control in ipairs(ns.Settings.controls) do
            if control.setting.section then
                firstGrouped = firstGrouped or index
            else
                lastMain = index
            end
        end

        assertTrue(firstGrouped > lastMain, "the group comes after everything else")
    end)

    it("orders the bottom group: clock settings, end caps, then the status text pair", function()
        local ns, env = loggedIn()

        local grouped = {}
        for _, control in ipairs(ns.Settings.controls) do
            if control.setting.section then
                table.insert(grouped, control.setting.key)
            end
        end

        assertEqual("hideBlizzardClock", grouped[1])
        assertEqual("hideEndCaps", grouped[2])
        assertEqual("showStatusText", grouped[3])
        assertEqual("statusTextSize", grouped[4])
    end)

    -- 12/24 hour belongs to the clock block, so it reads as part of it rather
    -- than as a separate line that happens to mention a clock.
    it("indents a sub-option directly under its parent", function()
        local ns, env = loggedIn()

        local index
        for position, control in ipairs(ns.Settings.controls) do
            if control.setting.key == "clock" and control.setting.store == "modules" then
                index = position
            end
        end

        local child = ns.Settings.controls[index + 1]
        assertEqual("use24Hour", child.setting.key, "sits right under Show clock")
        assertEqual(1, child.depth, "and is indented")
    end)

    it("places a sub-option by its parent, whatever order it was declared in", function()
        local ns = helpers.loadAddon()

        -- use24Hour is registered in Clock.lua before the module itself, so
        -- registration order alone would put it in the wrong place.
        local declaredFirst
        for _, setting in ipairs(ns.settings) do
            if setting.key == "use24Hour" or (setting.store == "modules" and setting.key == "clock") then
                declaredFirst = declaredFirst or setting.key
            end
        end

        assertEqual("use24Hour", declaredFirst, "the child is declared first")
    end)

    it("builds a control for every registered setting", function()
        local ns, env = loggedIn()

        local controls = ns.Settings.controls
        assertEqual(#ns.settings, #controls, "one control each")
    end)

    -- Opening the panel this way leaves the client queued to fall back to the
    -- game menu when it closes, which is not where the player came from.
    it("does not leave the game menu behind when it closes", function()
        local ns, env = loggedIn()

        ns.OpenSettings()
        env.SettingsPanel.scripts.OnHide(env.SettingsPanel)

        -- The client shows the game menu as part of closing the panel. It has
        -- to go in the same frame, or the player sees it flash up first.
        env.GameMenuFrame:Show()

        assertFalse(env.GameMenuFrame:IsShown(), "gone before a frame is drawn")
    end)

    it("leaves the game menu alone when the player opened it themselves", function()
        local ns, env = loggedIn()

        -- Open and close once through our menu, so the hook is in place and
        -- that close has finished settling.
        ns.OpenSettings()
        env.SettingsPanel.scripts.OnHide(env.SettingsPanel)
        env.__runTimers()

        -- Now the panel is reached through the game menu instead, so closing it
        -- should go back there as the client intends.
        env.SettingsPanel.scripts.OnHide(env.SettingsPanel)
        env.GameMenuFrame:Show()
        env.__runTimers()

        assertTrue(env.GameMenuFrame:IsShown(), "left where the client put it")
    end)

    it("shows the stored value when opened", function()
        local ns, env = loggedIn()

        -- Flipped away from its default, so a control that ignores the
        -- database entirely cannot pass this by accident.
        ns.db.bar.pushUIDown = false
        ns.Settings.Refresh()

        for _, control in ipairs(ns.Settings.controls) do
            if control.setting.key == "pushUIDown" then
                assertFalse(control.widget:GetChecked(), "reflects the database")
                return
            end
        end

        error("no control for pushUIDown")
    end)
end)
