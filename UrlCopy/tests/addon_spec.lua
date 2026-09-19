local helpers = require("helpers")

local ONLY_CORE = { "UrlCopy.lua" }

describe("the database", function()
    it("applies defaults at login", function()
        local ns, env = helpers.loadAddon(ONLY_CORE)
        helpers.login(ns, env)

        assertEqual(1, ns.db.version, "the version default is there")
    end)

    it("lets a stored value win over a default", function()
        local ns, env = helpers.loadAddon(ONLY_CORE)
        env.UrlCopyDB = { version = 99 }
        helpers.login(ns, env)

        assertEqual(99, ns.db.version, "the stored value survives")
    end)

    it("fills in a nested table added since the value was saved", function()
        local ns, env = helpers.loadAddon(ONLY_CORE)
        ns.AddDefaults({ later = { added = "yes" } })
        env.UrlCopyDB = { version = 1 }
        helpers.login(ns, env)

        assertEqual("yes", ns.db.later.added, "the new branch is filled in")
    end)
end)

describe("commands", function()
    it("runs a registered command", function()
        local ns, env = helpers.loadAddon(ONLY_CORE)
        local got
        ns.RegisterCommand("ping", "Ping", function(rest) got = rest end)
        helpers.login(ns, env)

        helpers.command(env, "ping there")
        assertEqual("there", got, "the rest of the line reaches the handler")
    end)

    it("lists every command under /url help", function()
        local ns, env = helpers.loadAddon(ONLY_CORE)
        ns.RegisterCommand("ping", "Ping the thing", function() end)
        helpers.login(ns, env)

        helpers.command(env, "help")
        assertMatch("Ping the thing", helpers.printed(env), "the help text is shown")
    end)

    it("shows the help lines that are not named commands", function()
        local ns, env = helpers.loadAddon(ONLY_CORE)
        ns.RegisterHelpLine("/url - Copy the most recent link")
        helpers.login(ns, env)

        helpers.command(env, "help")
        assertMatch("Copy the most recent link", helpers.printed(env))
    end)

    it("sends a bare /url to BareCommand, not to help", function()
        local ns, env = helpers.loadAddon(ONLY_CORE)
        local ran = false
        ns.BareCommand = function() ran = true end
        helpers.login(ns, env)

        helpers.command(env, "")
        assertTrue(ran, "the common case gets the shortest gesture")
    end)

    it("sends a number to NumberCommand", function()
        local ns, env = helpers.loadAddon(ONLY_CORE)
        local got
        ns.NumberCommand = function(index) got = index end
        helpers.login(ns, env)

        helpers.command(env, "3")
        assertEqual(3, got, "and as a number, not a string")
    end)

    it("says so for a command it does not know", function()
        local ns, env = helpers.loadAddon(ONLY_CORE)
        helpers.login(ns, env)

        helpers.command(env, "wibble")
        assertMatch("Unknown command", helpers.printed(env))
    end)
end)

describe("the setting registry", function()
    it("keeps settings in declaration order", function()
        local ns = helpers.loadAddon(ONLY_CORE)
        ns.AddDefaults({ box = { first = true, second = 2 } })

        ns.RegisterSetting({ store = "box", key = "first", type = "checkbox", name = "First" })
        ns.RegisterSetting({ store = "box", key = "second", type = "slider", name = "Second", min = 1, max = 3 })

        assertEqual("First", ns.settings[1].name)
        assertEqual("Second", ns.settings[2].name)
    end)

    it("refuses a setting with no default behind it", function()
        local ns = helpers.loadAddon(ONLY_CORE)

        -- A control wired to nothing renders fine and does nothing at all,
        -- which is the hardest kind of bug to see.
        assertErrors(function()
            ns.RegisterSetting({ store = "nowhere", key = "nothing", type = "checkbox", name = "No" })
        end)
    end)

    it("refuses a type it cannot render", function()
        local ns = helpers.loadAddon(ONLY_CORE)
        ns.AddDefaults({ box = { thing = 1 } })

        assertErrors(function()
            ns.RegisterSetting({ store = "box", key = "thing", type = "dial", name = "Dial" })
        end)
    end)
end)

describe("settings values", function()
    it("writes through and calls onChange", function()
        local ns, env = helpers.loadAddon(ONLY_CORE)
        ns.AddDefaults({ box = { flag = false } })
        local seen
        local setting = ns.RegisterSetting({
            store = "box", key = "flag", type = "checkbox", name = "Flag",
            onChange = function(value) seen = value end,
        })
        helpers.login(ns, env)

        ns.SetSettingValue(setting, true)
        assertTrue(ns.db.box.flag, "the database has it")
        assertTrue(seen, "and the owner was told")
    end)

    it("stays quiet when the value has not changed", function()
        local ns, env = helpers.loadAddon(ONLY_CORE)
        ns.AddDefaults({ box = { flag = false } })
        local calls = 0
        local setting = ns.RegisterSetting({
            store = "box", key = "flag", type = "checkbox", name = "Flag",
            onChange = function() calls = calls + 1 end,
        })
        helpers.login(ns, env)

        ns.SetSettingValue(setting, false)
        assertEqual(0, calls, "no change, no notification")
    end)
end)
