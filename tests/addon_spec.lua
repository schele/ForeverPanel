local helpers = require("helpers")

local plain = helpers.plain

describe("defaults", function()
    it("fills in nested config without clobbering stored values", function()
        local ns = helpers.loadAddon()

        local stored = { bar = { height = 40 } }
        ns.applyDefaults(stored, { bar = { height = 24, enabled = true }, other = 1 })

        assertEqual(40, stored.bar.height, "an existing value is kept")
        assertEqual(true, stored.bar.enabled, "a missing nested value is filled in")
        assertEqual(1, stored.other)
    end)

    it("creates tables that are missing entirely", function()
        local ns = helpers.loadAddon()

        local stored = {}
        ns.applyDefaults(stored, { bar = { height = 24 } })

        assertEqual(24, stored.bar.height)
    end)

    it("leaves a populated list alone", function()
        local ns = helpers.loadAddon()

        local stored = { notes = { "kept" } }
        ns.applyDefaults(stored, { notes = {} })

        assertEqual(1, #stored.notes)
        assertEqual("kept", stored.notes[1])
    end)
end)

describe("saved variables", function()
    it("adopts data saved under the old addon name", function()
        local ns, env = helpers.loadAddon()
        env.ForeverDB = { launches = 5, notes = { { at = "then", text = "old note" } } }

        helpers.login(ns, env)

        assertEqual(6, ns.db.launches, "launches carried over and incremented")
        assertEqual("old note", ns.db.notes[1].text)
    end)

    it("starts fresh when there is nothing saved", function()
        local ns, env = helpers.loadAddon()

        helpers.login(ns, env)

        assertEqual(1, ns.db.launches)
        assertEqual(0, #ns.db.notes)
        assertEqual(24, ns.db.bar.height)
        assertEqual(true, ns.db.bar.pushUIDown)
    end)
end)

describe("module registry", function()
    it("rejects a duplicate module name", function()
        local ns = helpers.loadAddon()

        assertErrors(function()
            ns.Bar:RegisterModule({ name = "money", side = "LEFT" })
        end)
    end)

    it("rejects an invalid side", function()
        local ns = helpers.loadAddon()

        assertErrors(function()
            ns.Bar:RegisterModule({ name = "nope", side = "TOP" })
        end)
    end)

    it("builds a module registered after login", function()
        local ns, env = helpers.loadAddon()
        helpers.login(ns, env)

        local created = false
        local module = ns.Bar:RegisterModule({
            name = "late",
            side = "LEFT",
            order = 99,
            OnCreate = function()
                created = true
            end,
        })
        env.__runTimers()

        assertTrue(created, "OnCreate ran for a late registration")
        assertTrue(module.frame ~= nil, "a frame was built")
    end)
end)

describe("the bar at login", function()
    it("creates a named bar frame parented to UIParent", function()
        local ns, env = helpers.loadAddon()
        helpers.login(ns, env)

        assertTrue(env.ForeverBar ~= nil, "the bar frame is globally named")
        assertEqual(env.UIParent, env.ForeverBar.parent)
        assertEqual(24, env.ForeverBar.height)
    end)

    it("reserves space by insetting UIParent from the top", function()
        local ns, env = helpers.loadAddon()
        helpers.login(ns, env)

        local point, _, relativePoint, x, y = env.UIParent:GetPoint(1)
        assertEqual("TOPLEFT", point)
        assertEqual("TOPLEFT", relativePoint)
        assertEqual(0, x)
        assertEqual(-24, y, "UIParent is pushed down by the bar height")
    end)

    it("anchors the bar into the strip above UIParent", function()
        local ns, env = helpers.loadAddon()
        helpers.login(ns, env)

        local point, relativeTo, relativePoint = env.ForeverBar:GetPoint(1)
        assertEqual("BOTTOMLEFT", point)
        assertEqual(env.UIParent, relativeTo)
        assertEqual("TOPLEFT", relativePoint)
    end)

    it("releases the reserved space when pushing is turned off", function()
        local ns, env = helpers.loadAddon()
        helpers.login(ns, env)

        helpers.command(env, "bar push")

        local _, _, _, _, y = env.UIParent:GetPoint(1)
        assertEqual(0, y, "UIParent goes back to full height")
        assertEqual("TOPLEFT", env.ForeverBar:GetPoint(1), "the bar overlays instead")
    end)

    it("follows a height change", function()
        local ns, env = helpers.loadAddon()
        helpers.login(ns, env)

        helpers.command(env, "bar height 32")

        assertEqual(32, ns.db.bar.height)
        assertEqual(32, env.ForeverBar.height)
        local _, _, _, _, y = env.UIParent:GetPoint(1)
        assertEqual(-32, y)
    end)

    it("clamps the height to the supported range", function()
        local ns, env = helpers.loadAddon()
        helpers.login(ns, env)

        helpers.command(env, "bar height 500")
        assertEqual(48, ns.db.bar.height)

        helpers.command(env, "bar height 1")
        assertEqual(16, ns.db.bar.height)
    end)

    it("hides the whole bar when toggled off", function()
        local ns, env = helpers.loadAddon()
        helpers.login(ns, env)

        helpers.command(env, "bar")

        assertFalse(ns.db.bar.enabled)
        assertFalse(env.ForeverBar:IsShown())
    end)
end)

describe("money module", function()
    it("shows the current money at login", function()
        local ns, env = helpers.loadAddon()
        env.money = 1234567
        helpers.login(ns, env)

        assertEqual("123 45 67", plain(ns.Bar:GetModule("money").text:GetText()))
    end)

    it("updates on PLAYER_MONEY", function()
        local ns, env = helpers.loadAddon()
        helpers.login(ns, env)

        env.money = 98765
        helpers.fire(env, "PLAYER_MONEY")

        assertEqual("9 87 65", plain(ns.Bar:GetModule("money").text:GetText()))
    end)

    it("sits on the right of the bar", function()
        local ns, env = helpers.loadAddon()
        helpers.login(ns, env)

        local module = ns.Bar:GetModule("money")
        assertEqual("RIGHT", module.frame:GetPoint(1))
        assertTrue(module.width > 0, "the module reports a width for layout")
    end)
end)

describe("clock module", function()
    it("renders the current time and sits in the centre", function()
        local ns, env = helpers.loadAddon()
        helpers.login(ns, env)

        local module = ns.Bar:GetModule("clock")
        assertMatch("^%d%d:%d%d$", module.text:GetText())
        assertEqual("CENTER", module.frame:GetPoint(1))
    end)

    it("toggles 12 and 24 hour on click", function()
        local ns, env = helpers.loadAddon()
        helpers.login(ns, env)

        local module = ns.Bar:GetModule("clock")
        module.frame.scripts.OnClick(module.frame, "LeftButton")

        assertFalse(ns.db.clock.use24Hour)
        assertMatch("[AP]M$", module.text:GetText())

        module.frame.scripts.OnClick(module.frame, "LeftButton")

        assertTrue(ns.db.clock.use24Hour)
        assertMatch("^%d%d:%d%d$", module.text:GetText())
    end)

    it("toggles 12 and 24 hour by command", function()
        local ns, env = helpers.loadAddon()
        helpers.login(ns, env)

        helpers.command(env, "clock")

        assertFalse(ns.db.clock.use24Hour)
        assertMatch("[AP]M$", ns.Bar:GetModule("clock").text:GetText())
    end)

    it("hides Blizzard's clock by default and keeps it hidden", function()
        local ns, env = helpers.loadAddon()
        helpers.login(ns, env)

        assertFalse(env.TimeManagerClockButton:IsShown())

        -- Blizzard code calling Show must not bring it back.
        env.TimeManagerClockButton:Show()
        assertFalse(env.TimeManagerClockButton:IsShown())
    end)

    it("gives Blizzard's clock back when the setting is turned off", function()
        local ns, env = helpers.loadAddon()
        helpers.login(ns, env)

        helpers.command(env, "clock blizzard")

        assertFalse(ns.db.clock.hideBlizzardClock)
        assertTrue(env.TimeManagerClockButton:IsShown())
    end)

    it("only rewrites the font string when the minute changes", function()
        local ns, env = helpers.loadAddon()
        helpers.login(ns, env)

        local module = ns.Bar:GetModule("clock")
        local before = module.text:GetText()
        module.text:SetText("sentinel")

        env.__tick()

        assertEqual("sentinel", module.text:GetText(), "an unchanged time leaves the text alone")
        assertEqual(before, module.lastText)
    end)
end)

describe("xp module", function()
    it("shows the remaining percentage on the left", function()
        local ns, env = helpers.loadAddon()
        env.xp, env.xpMax = 250, 1000
        helpers.login(ns, env)

        local module = ns.Bar:GetModule("xp")
        assertEqual("75.00% left", module.text:GetText())
        assertEqual("LEFT", module.frame:GetPoint(1))
        assertTrue(module.shown)
    end)

    it("updates on PLAYER_XP_UPDATE", function()
        local ns, env = helpers.loadAddon()
        env.xp, env.xpMax = 0, 1000
        helpers.login(ns, env)

        env.xp = 900
        helpers.fire(env, "PLAYER_XP_UPDATE")

        assertEqual("10.00% left", ns.Bar:GetModule("xp").text:GetText())
    end)

    it("hides itself at max level", function()
        local ns, env = helpers.loadAddon()
        env.xp, env.xpMax = 0, 0
        helpers.login(ns, env)

        local module = ns.Bar:GetModule("xp")
        assertFalse(module.shown)
        assertFalse(module.frame:IsShown())
    end)

    it("hides itself when XP gain is turned off", function()
        local ns, env = helpers.loadAddon()
        env.xp, env.xpMax = 100, 1000
        helpers.login(ns, env)
        assertTrue(ns.Bar:GetModule("xp").shown)

        env.xpDisabled = true
        helpers.fire(env, "DISABLE_XP_GAIN")

        assertFalse(ns.Bar:GetModule("xp").shown)
        assertFalse(ns.Bar:GetModule("xp").frame:IsShown())
    end)

    it("comes back when XP gain is re-enabled", function()
        local ns, env = helpers.loadAddon()
        env.xp, env.xpMax, env.xpDisabled = 100, 1000, true
        helpers.login(ns, env)
        assertFalse(ns.Bar:GetModule("xp").shown)

        env.xpDisabled = false
        helpers.fire(env, "ENABLE_XP_GAIN")

        assertTrue(ns.Bar:GetModule("xp").shown)
        assertTrue(ns.Bar:GetModule("xp").frame:IsShown())
    end)
end)

describe("slash commands", function()
    it("registers /foreverpanel and /fp", function()
        local _, env = helpers.loadAddon()

        assertEqual("/foreverpanel", env.SLASH_FOREVERPANEL1)
        assertEqual("/fp", env.SLASH_FOREVERPANEL2)
        assertTrue(type(env.SlashCmdList.FOREVERPANEL) == "function")
    end)

    it("exposes help for every registered command", function()
        local ns = helpers.loadAddon()

        for _, name in ipairs({ "status", "note", "last", "clear", "bar", "clock" }) do
            assertTrue(ns.commands[name] ~= nil, name .. " is registered")
            assertTrue(#ns.commands[name].help > 0, name .. " has help text")
        end
    end)

    it("still saves and reads notes", function()
        local ns, env = helpers.loadAddon()
        helpers.login(ns, env)

        helpers.command(env, "note hello there")

        assertEqual(1, #ns.db.notes)
        assertEqual("hello there", ns.db.notes[1].text)
    end)
end)
