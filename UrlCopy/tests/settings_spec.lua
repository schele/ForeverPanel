local helpers = require("helpers")

local function loggedIn()
    local ns, env = helpers.loadAddon()
    helpers.login(ns, env)
    ns.SettingsPanel.EnsureBuilt()
    return ns, env
end

--- The control on the panel for a store and key.
local function controlFor(ns, store, key)
    for _, control in ipairs(ns.SettingsPanel.controls) do
        if control.setting.store == store and control.setting.key == key then
            return control
        end
    end
end

describe("the declared settings", function()
    it("declares one for each thing the panel offers", function()
        local ns = loggedIn()

        assertTrue(controlFor(ns, "chat", "rewrite") ~= nil, "the master switch")
        assertTrue(controlFor(ns, "chat", "shorten") ~= nil, "shortening")
        assertTrue(controlFor(ns, "history", "size") ~= nil, "the history size")
    end)

    it("puts the master switch first", function()
        local ns = loggedIn()
        assertEqual("rewrite", ns.SettingsPanel.controls[1].setting.key)
    end)
end)

describe("the panel", function()
    it("registers itself with the game's options", function()
        local ns, env = loggedIn()
        assertTrue(env.__settingsCategory ~= nil, "a category was registered")
    end)

    it("builds once, however often it is asked", function()
        local ns = loggedIn()
        local before = #ns.SettingsPanel.controls

        ns.SettingsPanel.EnsureBuilt()
        assertEqual(before, #ns.SettingsPanel.controls, "no second set of controls")
    end)

    it("shows the stored value when it refreshes", function()
        local ns = loggedIn()
        ns.db.chat.rewrite = false
        ns.SettingsPanel.Refresh()

        assertFalse(controlFor(ns, "chat", "rewrite").widget:GetChecked())
    end)

    it("writes a checkbox through to the database", function()
        local ns = loggedIn()
        local control = controlFor(ns, "chat", "shorten")

        control.widget:SetChecked(true)
        control.widget.scripts.OnClick(control.widget)

        assertTrue(ns.db.chat.shorten)
    end)

    it("opens from /url settings", function()
        local ns, env = loggedIn()
        helpers.command(env, "settings")

        assertEqual("category-id", env.__openedCategory)
    end)
end)

describe("the history slider", function()
    it("writes through to the database", function()
        local ns = loggedIn()
        controlFor(ns, "history", "size").widget:SetValue(4)

        assertEqual(4, ns.db.history.size)
    end)

    it("trims the history at once, so the list matches the number shown", function()
        local ns, env = loggedIn()
        for index = 1, 8 do
            ns.History.Add("site" .. index .. ".com")
        end

        controlFor(ns, "history", "size").widget:SetValue(3)
        assertEqual(3, #ns.History.All())
    end)
end)
