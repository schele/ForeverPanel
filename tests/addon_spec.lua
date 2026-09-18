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

    -- UIParent's top edge is wherever the inset put it, and Blizzard re-anchors
    -- UIParent at times of its own choosing. A bar hung off that edge sits above
    -- the top of the screen whenever the inset is not in force, which is
    -- invisible rather than merely misplaced. The bar belongs to the screen.
    it("anchors the bar to the screen, not to UIParent's movable top edge", function()
        local ns, env = helpers.loadAddon()
        helpers.login(ns, env)

        local point, relativeTo, relativePoint, _, y = env.ForeverBar:GetPoint(1)
        assertEqual("TOPLEFT", point)
        assertEqual(env.WorldFrame, relativeTo, "anchored to the screen")
        assertEqual("TOPLEFT", relativePoint)
        assertEqual(0, y, "flush with the top of the screen")
    end)

    it("stays on screen when the UIParent inset does not take", function()
        local ns, env = helpers.loadAddon()
        helpers.login(ns, env)

        -- Blizzard putting UIParent back at full screen height.
        env.UIParent:ClearAllPoints()
        ns.Bar:Update()

        local point, relativeTo = env.ForeverBar:GetPoint(1)
        assertEqual("TOPLEFT", point, "still pinned to the top of the screen")
        assertEqual(env.WorldFrame, relativeTo, "the bar does not follow UIParent")
        assertTrue(env.ForeverBar:IsShown(), "and is still shown")
    end)

    -- The inset call itself succeeds, and then UIParent is back at full height
    -- by the time anything looks: Blizzard re-anchors it after login. Watch for
    -- that instead of trying to guess the one moment it happens.
    it("puts the inset back when something else re-anchors UIParent", function()
        local ns, env = helpers.loadAddon()
        helpers.login(ns, env)
        helpers.firstFrame(env)

        env.UIParent:ClearAllPoints()
        env.UIParent:SetPoint("TOPLEFT", nil, "TOPLEFT", 0, 0)
        env.__runTimers()

        local point, _, _, _, y = env.UIParent:GetPoint(1)
        assertEqual("TOPLEFT", point)
        assertEqual(-24, y, "the inset is back")
    end)

    it("does not fight itself while applying the inset", function()
        local ns, env = helpers.loadAddon()
        helpers.login(ns, env)
        helpers.firstFrame(env)

        -- Re-applying must not queue another re-apply off its own SetPoint
        -- calls, or the bar spends every frame re-anchoring UIParent.
        ns.Bar.ApplyUIParentInset()
        assertEqual(0, #env.__timers, "no re-apply queued by our own call")
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

    it("sits on the left of the bar", function()
        local ns, env = helpers.loadAddon()
        helpers.login(ns, env)
        helpers.firstFrame(env)

        local module = ns.Bar:GetModule("money")
        assertEqual("LEFT", module.frame:GetPoint(1))
        assertTrue(module.width > 0, "the module reports a width for layout")
    end)
end)

describe("the default layout", function()
    it("puts money and xp on the left, the clock alone on the right", function()
        local ns, env = helpers.loadAddon()
        helpers.login(ns, env)

        assertEqual("LEFT", ns.Bar:GetModule("money").side)
        assertEqual("LEFT", ns.Bar:GetModule("xp").side)
        assertEqual("RIGHT", ns.Bar:GetModule("clock").side)

        -- The LEFT side flows left-to-right, so money reads first.
        assertTrue(
            ns.Bar:GetModule("money").order < ns.Bar:GetModule("xp").order,
            "money sits left of the xp block"
        )
    end)
end)

describe("the bar's backdrop", function()
    it("is a vertical gradient, dark at the bottom", function()
        local ns, env = helpers.loadAddon()
        helpers.login(ns, env)

        local gradient = env.ForeverBar.background.gradient
        assertTrue(gradient ~= nil, "the backdrop is a gradient, not a flat fill")
        assertEqual("VERTICAL", gradient.orientation)
        assertTrue(gradient.from.r < gradient.to.r, "the bottom is darker than the top")
    end)

    it("falls back to a flat fill on a client without SetGradient", function()
        local ns = helpers.loadAddon()

        local texture = {
            SetColorTexture = function(self, r, g, b, a)
                self.fill = { r, g, b, a }
            end,
        }

        assertEqual(false, ns.Bar.PaintBackground(texture), "the gradient call failed")
        assertTrue(texture.fill ~= nil, "it still got a colour")
        assertTrue(texture.fill[1] < 0.2, "and it is the dark end, not white")
    end)
end)

describe("the bar's edge", function()
    it("runs along the bottom, full width, at a fixed thickness", function()
        local ns, env = helpers.loadAddon()
        helpers.login(ns, env)

        local border = env.ForeverBar.border
        assertTrue(border ~= nil, "the bar has a border texture")
        assertEqual("BOTTOMLEFT", border:GetPoint(1))
        assertEqual(2, border:GetHeight(), "stays thin whatever the bar height")

        -- A taller bar must not thicken the edge with it.
        helpers.command(env, "bar height 48")
        assertEqual(2, border:GetHeight())
    end)
end)

describe("module text colour", function()
    -- The bar owns this, not the modules: GameFontNormal is WoW gold, which is
    -- also the bar's background, so a module left to its own devices renders
    -- invisible text. Doing it centrally means a new module cannot get it wrong.
    it("colours every module's text, including one registered after login", function()
        local ns, env = helpers.loadAddon()
        helpers.login(ns, env)

        ns.Bar:RegisterModule({
            name = "latecomer",
            OnCreate = function(module)
                module.text = module.frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            end,
            OnUpdate = function() end,
        })

        for _, name in ipairs({ "money", "clock", "xp", "latecomer" }) do
            local r, g, b = ns.Bar:GetModule(name).text:GetTextColor()
            assertEqual(1, r, name .. " red")
            assertEqual(1, g, name .. " green")
            assertEqual(1, b, name .. " blue")
        end
    end)
end)

describe("the first frame after login", function()
    -- The client cannot measure a font string until it has been laid out, so
    -- every module measures 0 during login. The bar has to re-measure once the
    -- first frame has been drawn, or it keeps the zero widths and the modules
    -- pile up instead of spreading across the bar.
    it("measures every module once the text has been laid out", function()
        local ns, env = helpers.loadAddon()
        helpers.login(ns, env)
        helpers.firstFrame(env)

        for _, name in ipairs({ "money", "clock" }) do
            local module = ns.Bar:GetModule(name)
            assertTrue(module.width > 0, name .. " is measured after the first frame")
            -- Zero-width modules collapse to the 1px minimum, which is what
            -- leaves their text piled up at the anchor instead of laid out.
            assertTrue(module.frame:GetWidth() > 1, name .. " is wider than the placeholder")
        end
    end)

    it("re-measures without waiting for an unrelated event", function()
        local ns, env = helpers.loadAddon()
        helpers.login(ns, env)
        helpers.firstFrame(env)

        local money = ns.Bar:GetModule("money")
        local measured = money.width

        -- Nothing about the player's money changed; the width came from the
        -- re-measure alone, not from a PLAYER_MONEY refresh happening to land.
        helpers.fire(env, "PLAYER_MONEY")
        assertEqual(measured, money.width, "the login measurement already matched")
    end)
end)

describe("clock module", function()
    it("renders the current time at the right edge", function()
        local ns, env = helpers.loadAddon()
        helpers.login(ns, env)

        local module = ns.Bar:GetModule("clock")
        assertMatch("^%d%d:%d%d$", module.text:GetText())
        assertEqual("RIGHT", module.frame:GetPoint(1))
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
    it("counts the earned percentage up by default, on the left", function()
        local ns, env = helpers.loadAddon()
        env.xp, env.xpMax = 250, 1000
        helpers.login(ns, env)

        local module = ns.Bar:GetModule("xp")
        assertEqual("25.00% XP", module.text:GetText())
        assertEqual("LEFT", module.frame:GetPoint(1))
        assertTrue(module.shown)
    end)

    it("toggles between counting up and counting down on click", function()
        local ns, env = helpers.loadAddon()
        env.xp, env.xpMax = 250, 1000
        helpers.login(ns, env)

        local module = ns.Bar:GetModule("xp")
        local click = module.frame:GetScript("OnClick")

        click(module.frame, "LeftButton")
        assertEqual("75.00% left", module.text:GetText(), "counts down after one click")

        click(module.frame, "LeftButton")
        assertEqual("25.00% XP", module.text:GetText(), "and back up after another")
    end)

    it("remembers the direction across a login", function()
        local first, firstEnv = helpers.loadAddon()
        firstEnv.xp, firstEnv.xpMax = 250, 1000
        helpers.login(first, firstEnv)

        local module = first.Bar:GetModule("xp")
        module.frame:GetScript("OnClick")(module.frame, "LeftButton")

        local second, secondEnv = helpers.loadAddon()
        secondEnv.ForeverPanelDB = firstEnv.ForeverPanelDB
        secondEnv.xp, secondEnv.xpMax = 250, 1000
        helpers.login(second, secondEnv)

        assertEqual("75.00% left", second.Bar:GetModule("xp").text:GetText())
    end)

    it("re-measures when the direction changes", function()
        local ns, env = helpers.loadAddon()
        env.xp, env.xpMax = 250, 1000
        helpers.login(ns, env)
        helpers.firstFrame(env)

        local module = ns.Bar:GetModule("xp")
        local before = module.width
        module.frame:GetScript("OnClick")(module.frame, "LeftButton")
        env.__runTimers()

        -- "75.00% left" and "25.00% XP" are different lengths, so a stale width
        -- would leave the neighbouring modules overlapping it.
        assertTrue(module.width ~= before, "the width follows the new text")
    end)

    it("updates on PLAYER_XP_UPDATE", function()
        local ns, env = helpers.loadAddon()
        env.xp, env.xpMax = 0, 1000
        helpers.login(ns, env)

        env.xp = 900
        helpers.fire(env, "PLAYER_XP_UPDATE")

        assertEqual("90.00% XP", ns.Bar:GetModule("xp").text:GetText())
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
