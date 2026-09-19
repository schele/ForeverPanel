local helpers = require("helpers")

local FILES = { "UrlCopy.lua", "Detect.lua", "Popup.lua", "Chat.lua" }

local function loggedIn()
    local ns, env = helpers.loadAddon(FILES)
    helpers.login(ns, env)
    return ns, env
end

describe("clicking a link", function()
    it("opens the box on the URL the link carries", function()
        local ns, env = loggedIn()
        local shown = helpers.say(env, "go to https://example.com/a now")

        helpers.click(env, helpers.linkIn(shown))
        assertEqual("https://example.com/a", helpers.box(env):GetText())
    end)

    it("works for a link that has left the history", function()
        local ns, env = loggedIn()
        local shown = helpers.say(env, "go to https://example.com/a now")
        ns.History.Clear()

        -- The URL travels inside the link, not as an index into anything, so
        -- a link that has scrolled up keeps working after the list has moved on.
        helpers.click(env, helpers.linkIn(shown))
        assertEqual("https://example.com/a", helpers.box(env):GetText())
    end)

    it("ignores every other kind of link", function()
        local ns, env = loggedIn()
        helpers.click(env, "item:6948:0:0:0")

        assertNil(helpers.box(env), "no box for an item link")
    end)

    it("survives a click with no link at all", function()
        local ns, env = loggedIn()
        helpers.click(env, nil)

        assertNil(helpers.box(env))
    end)
end)

describe("/url", function()
    it("opens the box on the most recent link", function()
        local ns, env = loggedIn()
        helpers.say(env, "first a.com")
        helpers.say(env, "then b.com")

        helpers.command(env, "")
        assertEqual("b.com", helpers.box(env):GetText())
    end)

    it("says so when nothing has been seen", function()
        local ns, env = loggedIn()
        helpers.command(env, "")

        assertNil(helpers.box(env))
        assertMatch("No link", helpers.printed(env))
    end)
end)

describe("/url <n>", function()
    it("opens the box on the nth link", function()
        local ns, env = loggedIn()
        helpers.say(env, "first a.com")
        helpers.say(env, "then b.com")

        helpers.command(env, "2")
        assertEqual("a.com", helpers.box(env):GetText())
    end)

    it("says so when there is no such link", function()
        local ns, env = loggedIn()
        helpers.command(env, "7")

        assertNil(helpers.box(env))
        assertMatch("No link 7", helpers.printed(env))
    end)
end)

describe("/url list", function()
    it("numbers what it is remembering", function()
        local ns, env = loggedIn()
        helpers.say(env, "a.com and b.com")

        helpers.command(env, "list")
        assertMatch("1%.", helpers.printed(env))
        assertMatch("2%.", helpers.printed(env))
    end)

    it("prints clickable links even with rewriting switched off", function()
        local ns, env = loggedIn()
        ns.db.chat.rewrite = false
        helpers.say(env, "a.com")

        helpers.command(env, "list")
        -- With the switch off this is the only way left to click one, and it
        -- is a direct answer to a command rather than someone else's message.
        assertMatch("|Hurlcopy:a%.com|h", helpers.printed(env))
    end)

    it("says so when there is nothing to list", function()
        local ns, env = loggedIn()
        helpers.command(env, "list")

        assertMatch("No links", helpers.printed(env))
    end)
end)

describe("/url clear", function()
    it("forgets everything", function()
        local ns, env = loggedIn()
        helpers.say(env, "a.com")

        helpers.command(env, "clear")
        assertEqual(0, #ns.History.All())
    end)
end)

describe("/url on and /url off", function()
    it("stops chat being touched", function()
        local ns, env = loggedIn()
        helpers.command(env, "off")

        assertFalse(ns.db.chat.rewrite)
        assertEqual("see a.com", helpers.say(env, "see a.com"))
    end)

    it("starts it again", function()
        local ns, env = loggedIn()
        helpers.command(env, "off")
        helpers.command(env, "on")

        assertTrue(ns.db.chat.rewrite)
        assertMatch("|Hurlcopy:", helpers.say(env, "see a.com"))
    end)
end)

describe("help", function()
    it("mentions the bare and numeric forms, which are not named commands", function()
        local ns, env = loggedIn()
        helpers.command(env, "help")

        local printed = helpers.printed(env)
        assertMatch("/url %-", printed, "the bare form is documented")
        assertMatch("/url <n>", printed, "and the numeric one")
    end)
end)
