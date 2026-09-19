local helpers = require("helpers")

local FILES = { "UrlCopy.lua", "Detect.lua", "Popup.lua", "Chat.lua" }

local function loggedIn()
    local ns, env = helpers.loadAddon(FILES)
    helpers.login(ns, env)
    return ns, env
end

describe("the history", function()
    it("starts empty", function()
        local ns = loggedIn()
        assertEqual(0, #ns.History.All())
    end)

    it("keeps the newest first", function()
        local ns = loggedIn()
        ns.History.Add("a.com")
        ns.History.Add("b.com")

        assertEqual("b.com", ns.History.Get(1), "the one just seen")
        assertEqual("a.com", ns.History.Get(2))
    end)

    it("moves a repeat to the front instead of duplicating it", function()
        local ns = loggedIn()
        ns.History.Add("a.com")
        ns.History.Add("b.com")
        ns.History.Add("a.com")

        assertEqual(2, #ns.History.All(), "still two")
        assertEqual("a.com", ns.History.Get(1), "and the repeat is the newest")
    end)

    it("ignores an empty URL", function()
        local ns = loggedIn()
        ns.History.Add("")
        ns.History.Add(nil)

        assertEqual(0, #ns.History.All())
    end)

    it("holds no more than the configured size", function()
        local ns = loggedIn()
        ns.db.history.size = 3

        for index = 1, 10 do
            ns.History.Add("site" .. index .. ".com")
        end

        assertEqual(3, #ns.History.All())
        assertEqual("site10.com", ns.History.Get(1), "the newest survives")
        assertEqual("site8.com", ns.History.Get(3), "the oldest three do not")
    end)

    it("trims on demand, so the list matches the number on the panel", function()
        local ns = loggedIn()
        for index = 1, 5 do
            ns.History.Add("site" .. index .. ".com")
        end

        ns.History.Trim(2)
        assertEqual(2, #ns.History.All())
        assertEqual("site5.com", ns.History.Get(1))
    end)

    it("empties the list when trimmed to zero", function()
        local ns = loggedIn()
        ns.History.Add("a.com")
        ns.History.Add("b.com")

        ns.History.Trim(0)
        assertEqual(0, #ns.History.All())
    end)

    it("does not hang on a negative size and leaves the list empty", function()
        local ns = loggedIn()
        ns.History.Add("a.com")
        ns.History.Add("b.com")

        ns.History.Trim(-1)
        assertEqual(0, #ns.History.All())
    end)

    it("falls back to ten when given nil or unparseable sizes", function()
        local ns = loggedIn()
        for index = 1, 15 do
            ns.History.Add("site" .. index .. ".com")
        end

        ns.History.Trim(nil)
        assertEqual(10, #ns.History.All(), "nil falls back to 10")

        for index = 1, 15 do
            ns.History.Add("more" .. index .. ".com")
        end

        ns.History.Trim("banana")
        assertEqual(10, #ns.History.All(), "unparseable also falls back to 10")
    end)

    it("forgets everything when cleared", function()
        local ns = loggedIn()
        ns.History.Add("a.com")
        ns.History.Clear()

        assertEqual(0, #ns.History.All())
        assertNil(ns.History.Get(1))
    end)

    it("hands out a copy, not the list itself", function()
        local ns = loggedIn()
        ns.History.Add("a.com")

        local all = ns.History.All()
        all[1] = "tampered.com"

        assertEqual("a.com", ns.History.Get(1), "the real list is untouched")
    end)
end)

describe("history defaults", function()
    it("remembers ten by default", function()
        local ns = loggedIn()
        assertEqual(10, ns.db.history.size)
    end)

    it("rewrites chat by default", function()
        local ns = loggedIn()
        -- The addon's entire point is clickable links, and on a client that
        -- forgets its SavedVariables, off by default means off every login.
        assertTrue(ns.db.chat.rewrite)
    end)

    it("shows links in full by default", function()
        local ns = loggedIn()
        assertFalse(ns.db.chat.shorten)
    end)
end)
