local helpers = require("helpers")

local function loggedIn()
    local ns, env = helpers.loadAddon()
    helpers.login(ns, env)

    -- The feature ships off, so these tests say so rather than inheriting
    -- whatever the default happens to be.
    ns.db.chat.enabled = true
    ns.ChatKeys.Apply()

    return ns, env
end

--- Press the key that row's button is bound to.
local function pressRow(ns, env, index)
    local button = env["ForeverPanelChatKey" .. index]
    button.scripts.OnClick(button)
    return env.__chatOpenedWith
end

describe("chat keys while switched off", function()
    it("is bound from login, since nothing off by default survives here", function()
        local ns, env = helpers.loadAddon()
        helpers.login(ns, env)

        assertTrue(ns.db.chat.enabled, "ships on")
        assertEqual("ForeverPanelChatKey2", env.__overrideBindings["CTRL-G"], "bound from login")
    end)

    it("creates nothing whatsoever once it is switched off", function()
        local ns, env = helpers.loadAddon()
        env.ForeverPanelDB = { chat = { enabled = false } }
        helpers.login(ns, env)

        assertFalse(ns.db.chat.enabled, "the stored choice wins over the default")
        assertTrue(next(env.__overrideBindings) == nil, "no key is taken")
        assertTrue(env.ForeverPanelChatKey1 == nil, "not even the buttons exist")
    end)

    it("releases every binding the moment it is switched off", function()
        local ns, env = loggedIn()
        assertTrue(env.__overrideBindings["CTRL-S"] ~= nil, "bound while on")

        ns.db.chat.enabled = false
        ns.ChatKeys.Apply()

        assertTrue(next(env.__overrideBindings) == nil, "and let go when off")
    end)

    it("still keeps the table, so it is ready when switched back on", function()
        local ns, env = helpers.loadAddon()
        helpers.login(ns, env)

        assertEqual("CTRL-S", ns.db.chat.keys[1].key, "rows are still seeded")
    end)
end)

describe("chat key rows", function()
    it("seeds a working set at login", function()
        local ns, env = loggedIn()

        local rows = ns.db.chat.keys
        assertEqual("CTRL-S", rows[1].key)
        assertEqual("/s", rows[1].command)
        assertTrue(#rows > 1, "more than one to start with")
    end)

    it("binds each filled row to its own button", function()
        local ns, env = loggedIn()

        assertEqual("ForeverPanelChatKey1", env.__overrideBindings["CTRL-S"])
        assertEqual("ForeverPanelChatKey2", env.__overrideBindings["CTRL-G"])
    end)

    it("leaves a half-filled row unbound", function()
        local ns, env = loggedIn()

        ns.db.chat.keys[1].command = ""
        ns.ChatKeys.Apply()

        assertTrue(env.__overrideBindings["CTRL-S"] == nil, "nothing to open, so nothing bound")
    end)

    it("opens chat with the command and a trailing space", function()
        local ns, env = loggedIn()

        assertEqual("/s ", pressRow(ns, env, 1), "cursor lands after the command")
    end)

    it("follows a row that has been retyped", function()
        local ns, env = loggedIn()

        ns.db.chat.keys[1].command = "/raid"
        ns.ChatKeys.Apply()

        assertEqual("/raid ", pressRow(ns, env, 1))
    end)

    it("rebinds when a key is changed", function()
        local ns, env = loggedIn()

        ns.db.chat.keys[1].key = "ALT-Q"
        ns.ChatKeys.Apply()

        assertTrue(env.__overrideBindings["CTRL-S"] == nil, "the old key is released")
        assertEqual("ForeverPanelChatKey1", env.__overrideBindings["ALT-Q"])
    end)
end)

local function keyTable(ns)
    -- The panel builds on first open, so these tests open it.
    ns.Settings.EnsureBuilt()

    for _, control in ipairs(ns.Settings.controls) do
        if control.setting.type == "keytable" then
            return control
        end
    end
end

describe("the chat key table on the panel", function()
    it("stops capturing once you click into the command box", function()
        local ns, env = loggedIn()
        local row = keyTable(ns).rows[1]

        row.capture.scripts.OnClick(row.capture)
        assertTrue(row.capture.keyboardEnabled, "armed by the click")

        row.command.scripts.OnEditFocusGained(row.command)
        assertFalse(row.capture.keyboardEnabled, "disarmed on moving away")

        -- Typing a slash is Shift+7 on some layouts, which would otherwise be
        -- swallowed by the still-armed capture and rebind the row.
        env.modifiers = { shift = true }
        row.capture.scripts.OnKeyDown(row.capture, "7")

        assertEqual("CTRL-S", ns.db.chat.keys[1].key, "the key is untouched")
    end)

    -- A focused edit box swallows Escape unless it is given something to do
    -- with it, which leaves the whole options window refusing to close.
    it("lets escape out of a command box instead of swallowing it", function()
        local ns, env = loggedIn()
        local row = keyTable(ns).rows[1]

        assertTrue(row.command:GetScript("OnEscapePressed") ~= nil, "escape is handled")

        row.command.scripts.OnEditFocusGained(row.command)
        row.command:SetText("/half-typed")
        row.command.scripts.OnEscapePressed(row.command)

        assertEqual("/s", ns.db.chat.keys[1].command, "the half-typed edit was abandoned")
        assertEqual("/s", row.command:GetText(), "and the box shows the stored value again")
    end)

    -- An EditBox takes focus as it comes into existence, and SetAutoFocus(false)
    -- runs a line too late to stop it. Built while the panel is already open,
    -- the first box swallows backspace, escape and the arrow keys.
    it("takes focus off every box as it is created", function()
        local ns, env = loggedIn()

        for _, row in ipairs(keyTable(ns).rows) do
            assertTrue(row.command.focusCleared, "row " .. row.index .. " does not hold focus")
        end
    end)

    -- A frame with an OnKeyDown script swallows the key unless it says
    -- otherwise. Printable characters reach the focused edit box by another
    -- path, which is why typing worked while backspace, arrows and escape did
    -- not: the capture button beside it was eating them.
    it("passes keys through except while it is listening for one", function()
        local ns, env = loggedIn()
        local row = keyTable(ns).rows[1]

        assertFalse(row.capture.keyboardEnabled, "not listening to begin with")
        assertTrue(row.capture.propagateKeys, "so keys reach the rest of the UI")

        row.capture.scripts.OnClick(row.capture)
        assertFalse(row.capture.propagateKeys, "holds onto them while capturing")

        row.capture.scripts.OnKeyDown(row.capture, "ESCAPE")
        assertTrue(row.capture.propagateKeys, "and hands them straight back")
    end)

    it("only ever has one row armed", function()
        local ns, env = loggedIn()
        local rows = keyTable(ns).rows

        rows[1].capture.scripts.OnClick(rows[1].capture)
        rows[2].capture.scripts.OnClick(rows[2].capture)

        assertFalse(rows[1].capture.keyboardEnabled, "the first one gave way")
        assertTrue(rows[2].capture.keyboardEnabled)
    end)

    -- A capture left listening, or an edit box left focused, holds the whole
    -- keyboard: no key reaches the game at all, including Escape.
    it("gives the keyboard back whenever the panel opens or closes", function()
        local ns, env = loggedIn()
        local row = keyTable(ns).rows[1]

        row.capture.scripts.OnClick(row.capture)
        assertTrue(row.capture.keyboardEnabled, "armed")

        ns.Settings.ReleaseKeyboard()

        assertFalse(row.capture.keyboardEnabled, "the capture let go")
        assertTrue(row.command.focusCleared, "and the boxes dropped focus")
    end)

    it("sits in a second column, not below everything else", function()
        local ns, env = loggedIn()

        local _, captureX = keyTable(ns).rows[1].capture:GetPoint(1)

        local checkbox
        for _, control in ipairs(ns.Settings.controls) do
            if control.setting.key == "pushUIDown" then
                checkbox = control
            end
        end
        local _, checkboxX = checkbox.widget:GetPoint(1)

        assertTrue(captureX > checkboxX + 200, "well right of the first column")
    end)
end)

-- Bindings applied during login do not survive: the client loads its own
-- binding set afterwards and ours go with it. Watch for that rather than
-- assuming one application at login is enough.
describe("keeping the bindings applied", function()
    -- Our own ClearOverrideBindings and SetOverrideBindingClick raise
    -- UPDATE_BINDINGS, and it arrives after Apply has returned. Re-applying on
    -- it meant every apply caused another one: the whole binding set torn down
    -- and rebuilt every frame, which reads as a keyboard that does not work.
    it("never re-applies in response to a binding change", function()
        local ns, env = loggedIn()

        local applies = 0
        local real = ns.ChatKeys.Apply
        ns.ChatKeys.Apply = function(...)
            applies = applies + 1
            return real(...)
        end

        helpers.fire(env, "UPDATE_BINDINGS")
        env.__runTimers()
        env.__runTimers()

        ns.ChatKeys.Apply = real
        assertEqual(0, applies, "a binding change must not feed itself back in")
    end)

    it("applies them once the world has finished loading", function()
        local ns, env = loggedIn()

        env.__overrideBindings = {}
        helpers.fire(env, "PLAYER_ENTERING_WORLD")

        assertEqual("ForeverPanelChatKey2", env.__overrideBindings["CTRL-G"])
    end)

end)

describe("chat keys in combat", function()
    it("does not touch bindings while locked down", function()
        local ns, env = loggedIn()
        env.__overrideBindings = {}
        env.__inCombat = true

        ns.db.chat.keys[1].key = "ALT-Q"
        ns.ChatKeys.Apply()

        assertTrue(env.__overrideBindings["ALT-Q"] == nil, "bindings are protected in combat")
    end)

    it("applies what it held back once combat ends", function()
        local ns, env = loggedIn()
        env.__inCombat = true

        ns.db.chat.keys[1].key = "ALT-Q"
        ns.ChatKeys.Apply()

        env.__inCombat = false
        helpers.fire(env, "PLAYER_REGEN_ENABLED")

        assertEqual("ForeverPanelChatKey1", env.__overrideBindings["ALT-Q"])
    end)
end)

describe("capturing a key combination", function()
    local function capture(ns, env, key, modifiers)
        env.modifiers = modifiers or {}
        return ns.ChatKeys.Combination(key)
    end

    -- Binding a bare letter takes that key globally, so B stops opening bags
    -- and the movement keys stop moving. A modifier is required.
    it("refuses a bare letter or digit", function()
        local ns, env = loggedIn()

        assertNil(capture(ns, env, "S"), "S alone would hijack the key")
        assertNil(capture(ns, env, "B"))
        assertNil(capture(ns, env, "7"))
    end)

    it("takes a bare function key, which is not in anyone's way", function()
        local ns, env = loggedIn()

        assertEqual("F5", capture(ns, env, "F5"))
        assertEqual("F12", capture(ns, env, "F12"))
    end)

    it("prefixes the held modifiers in the order WoW writes them", function()
        local ns, env = loggedIn()

        assertEqual("CTRL-S", capture(ns, env, "S", { ctrl = true }))
        assertEqual("ALT-CTRL-SHIFT-S", capture(ns, env, "S", { alt = true, ctrl = true, shift = true }))
    end)

    it("ignores a modifier pressed on its own", function()
        local ns, env = loggedIn()

        assertNil(capture(ns, env, "LCTRL", { ctrl = true }), "waits for a real key")
        assertNil(capture(ns, env, "RSHIFT", { shift = true }))
    end)

    it("ignores escape, so the capture can be abandoned", function()
        local ns, env = loggedIn()
        assertNil(capture(ns, env, "ESCAPE"))
    end)
end)
