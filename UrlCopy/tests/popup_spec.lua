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
        ns.Popup.Show("https://example.com/a")

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
        ns.Popup.Show("https://first.example.com")
        ns.Popup.Show("https://second.example.com")

        assertEqual("https://second.example.com", helpers.box(env):GetText())
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
