local helpers = require("helpers")

local function loggedIn()
    local ns, env = helpers.loadAddon()
    -- Give xp something to show, or it hides itself as at max level and never
    -- takes a position on the bar.
    env.xp, env.xpMax = 500, 1000
    helpers.login(ns, env)
    return ns, env
end

local function settingFor(ns, store, key)
    for _, setting in ipairs(ns.settings) do
        if setting.store == store and setting.key == key then
            return setting
        end
    end
end

describe("hiding a module", function()
    it("gives every module a visibility setting without the module asking", function()
        local ns = helpers.loadAddon()

        for _, name in ipairs({ "money", "clock", "xp" }) do
            assertTrue(settingFor(ns, "modules", name) ~= nil, name .. " can be hidden")
        end
    end)

    it("shows every module by default", function()
        local ns, env = loggedIn()

        for _, name in ipairs({ "money", "clock", "xp" }) do
            assertTrue(ns.db.modules[name], name .. " starts visible")
        end
    end)

    it("takes the module off the bar and closes the gap", function()
        local ns, env = loggedIn()
        helpers.firstFrame(env)

        local money = ns.Bar:GetModule("money")
        local xp = ns.Bar:GetModule("xp")
        local _, _, _, xpBefore = xp.frame:GetPoint(1)

        ns.SetSettingValue(settingFor(ns, "modules", "money"), false)
        env.__runTimers()

        assertFalse(money.frame:IsShown(), "the money frame is hidden")

        -- money sorts before xp on the left, so xp moves into its place.
        local _, _, _, xpAfter = xp.frame:GetPoint(1)
        assertTrue(xpAfter < xpBefore, "xp slid left into the gap")
    end)

    it("brings it back", function()
        local ns, env = loggedIn()
        local setting = settingFor(ns, "modules", "money")

        ns.SetSettingValue(setting, false)
        env.__runTimers()
        ns.SetSettingValue(setting, true)
        env.__runTimers()

        assertTrue(ns.Bar:GetModule("money").frame:IsShown())
    end)

    it("remembers across a login", function()
        local ns, env = loggedIn()
        ns.SetSettingValue(settingFor(ns, "modules", "clock"), false)

        local second, secondEnv = helpers.loadAddon()
        secondEnv.ForeverPanelDB = env.ForeverPanelDB
        helpers.login(second, secondEnv)
        secondEnv.__runTimers()

        assertFalse(second.Bar:GetModule("clock").frame:IsShown(), "still hidden")
    end)

    it("does not override a module that hides itself", function()
        local ns, env = helpers.loadAddon()
        env.xp, env.xpMax = 0, 0
        helpers.login(ns, env)
        helpers.firstFrame(env)

        -- At max level xp hides itself. Turning its setting on must not force
        -- an empty module back onto the bar.
        ns.SetSettingValue(settingFor(ns, "modules", "xp"), true)
        env.__runTimers()

        assertFalse(ns.Bar:GetModule("xp").frame:IsShown(), "still hidden at max level")
    end)
end)

describe("the action bar end caps", function()
    it("hides both at login, because the setting defaults on", function()
        local ns, env = loggedIn()

        assertFalse(env.MainActionBar.EndCaps.LeftEndCap:IsShown())
        assertFalse(env.MainActionBar.EndCaps.RightEndCap:IsShown())
    end)

    it("keeps them hidden when Blizzard shows them again", function()
        local ns, env = loggedIn()

        env.MainActionBar.EndCaps.LeftEndCap:Show()

        assertFalse(env.MainActionBar.EndCaps.LeftEndCap:IsShown(), "put back down")
    end)

    it("gives them back when turned off", function()
        local ns, env = loggedIn()

        ns.SetSettingValue(settingFor(ns, "ui", "hideEndCaps"), false)

        assertTrue(env.MainActionBar.EndCaps.LeftEndCap:IsShown(), "restored")
    end)
end)

describe("health and mana numbers", function()
    it("turns the game's own status text on at login, the setting defaulting on", function()
        local ns, env = loggedIn()

        assertEqual("1", env.__cvars.statusText)
        assertEqual("NUMERIC", env.__cvars.statusTextDisplay)
    end)

    -- The client's own status text is small and unoutlined, which is hard to
    -- read over a health bar. Restyle the font object every unit frame's text
    -- inherits from, rather than chasing individual font strings.
    it("makes the numbers bigger and outlined", function()
        local ns, env = loggedIn()

        local _, size, flags = env.TextStatusBarText:GetFont()
        assertEqual(ns.db.ui.statusTextSize, size)
        assertMatch("OUTLINE", flags)
    end)

    it("follows the size setting", function()
        local ns, env = loggedIn()

        ns.SetSettingValue(settingFor(ns, "ui", "statusTextSize"), 20)

        local _, size = env.TextStatusBarText:GetFont()
        assertEqual(20, size)
    end)

    it("puts the client's own font back when turned off", function()
        local ns, env = helpers.loadAddon()

        -- Read before logging in: the setting defaults on, so login already
        -- restyles the font. This is the font the client really started with.
        local _, originalSize, originalFlags = env.TextStatusBarText:GetFont()

        env.xp, env.xpMax = 500, 1000
        helpers.login(ns, env)
        ns.SetSettingValue(settingFor(ns, "ui", "showStatusText"), false)

        local _, size, flags = env.TextStatusBarText:GetFont()
        assertEqual(originalSize, size, "size restored")
        assertEqual(originalFlags, flags, "outline removed")
    end)

    it("turns it back off", function()
        local ns, env = loggedIn()

        ns.SetSettingValue(settingFor(ns, "ui", "showStatusText"), false)

        assertEqual("0", env.__cvars.statusText)
    end)
end)
