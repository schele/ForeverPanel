local helpers = require("helpers")

local FILES = { "UrlCopy.lua", "Detect.lua", "Popup.lua" }

local function loggedIn()
    local ns, env = helpers.loadAddon(FILES)
    helpers.login(ns, env)
    return ns, env
end

describe("the copy box", function()
    it("shows the URL", function()
        local ns, env = loggedIn()
        local dialog = ns.Popup.Show("https://example.com/a")

        assertTrue(dialog ~= nil, "returns the dialog")
        assertEqual(helpers.box(env), dialog.editBox, "whose editBox is the copy box")
        assertEqual("https://example.com/a", helpers.box(env):GetText())
    end)

    it("selects all of it, so one Ctrl+C takes the lot", function()
        local ns, env = loggedIn()
        ns.Popup.Show("https://example.com/a")

        assertTrue(helpers.box(env).highlighted, "the text is selected")
        assertTrue(helpers.box(env).focused, "and the box has the keyboard")
    end)

    it("replaces what it is showing when a second link is clicked", function()
        local ns, env = loggedIn()
        local firstDialog = ns.Popup.Show("https://first.example.com")
        local firstBox = helpers.box(env)

        local secondDialog = ns.Popup.Show("https://second.example.com")
        local secondBox = helpers.box(env)

        assertEqual(firstDialog, secondDialog, "reuses the same dialog")
        assertEqual(firstBox, secondBox, "reuses the same edit box")
        assertEqual("https://second.example.com", secondBox:GetText())
    end)

    it("puts the URL back when it is typed over", function()
        local ns, env = loggedIn()
        ns.Popup.Show("https://example.com/a")

        local box = helpers.box(env)
        box:SetText("nonsense")

        assertEqual("https://example.com/a", box:GetText(), "a copy box, not an edit box")
        assertTrue(box.highlighted, "and selected again, ready to copy")
    end)

    it("reports the URL it is holding", function()
        local ns = loggedIn()
        ns.Popup.Show("https://example.com/a")

        assertEqual("https://example.com/a", ns.Popup.Current())
    end)
end)

describe("the copy box with nothing to show", function()
    it("prints rather than opening an empty box", function()
        local ns, env = loggedIn()
        local dialog = ns.Popup.Show(nil)

        assertNil(dialog, "no box")
        assertMatch("No link", helpers.printed(env))
    end)

    it("treats an empty string the same way", function()
        local ns, env = loggedIn()
        assertNil(ns.Popup.Show(""))
        assertMatch("No link", helpers.printed(env))
    end)
end)

describe("the copy box when the edit box is missing", function()
    it("prints the link with a diagnostic when the box cannot be found", function()
        local ns, env = loggedIn()
        local dialog = ns.Popup.Show("https://example.com/test")

        -- Simulate a client that created a dialog but forgot the edit box.
        dialog.editBox = nil

        env.__printed = {}
        local result = ns.Popup.Show("https://example.com/broken")

        assertNil(result, "returns nil when the box is missing")
        assertMatch("Could not locate the copy box", helpers.printed(env))
        assertMatch("https://example.com/broken", helpers.printed(env))
    end)
end)
