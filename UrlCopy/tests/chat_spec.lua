local helpers = require("helpers")

local FILES = { "UrlCopy.lua", "Detect.lua", "Popup.lua", "Chat.lua" }

local function loggedIn()
    local ns, env = helpers.loadAddon(FILES)
    helpers.login(ns, env)
    return ns, env
end

describe("rewriting a message", function()
    it("wraps a URL in our own link type", function()
        local ns, env = loggedIn()
        local shown = helpers.say(env, "go to example.com now")

        assertMatch("|Hurlcopy:example%.com|h", shown, "the link carries the URL")
    end)

    it("colours and brackets the visible text", function()
        local ns, env = loggedIn()
        local shown = helpers.say(env, "go to example.com now")

        assertMatch("|cff66ccff%[example%.com%]|r", shown)
    end)

    it("leaves the rest of the sentence alone", function()
        local ns, env = loggedIn()
        local shown = helpers.say(env, "go to example.com now")

        assertMatch("^go to ", shown)
        assertMatch(" now$", shown)
    end)

    it("rewrites every URL in the line", function()
        local ns, env = loggedIn()
        local shown = helpers.say(env, "a.com and http://b.org/x")

        assertMatch("|Hurlcopy:a%.com|h", shown)
        assertMatch("|Hurlcopy:http://b%.org/x|h", shown)
    end)

    it("leaves a message with no URL untouched", function()
        local ns, env = loggedIn()
        local message = "just talking about nothing"

        assertEqual(message, helpers.say(env, message))
    end)

    it("never lets a pipe into a link", function()
        local ns, env = loggedIn()
        local shown = helpers.say(env, "http://evil.com|cffff0000nope|r")

        local link = helpers.linkIn(shown)
        assertEqual("urlcopy:http://evil.com", link, "the escape stayed outside")
    end)

    it("works in every channel it filters", function()
        local ns, env = loggedIn()

        for _, event in ipairs(ns.Chat.EVENTS) do
            local shown = env.__say(event, "see example.com", "Someone")
            assertMatch("|Hurlcopy:", shown, event .. " is filtered")
        end
    end)
end)

describe("rewriting switched off", function()
    it("leaves the message exactly as it was", function()
        local ns, env = loggedIn()
        ns.db.chat.rewrite = false

        local message = "go to example.com now"
        assertEqual(message, helpers.say(env, message))
    end)

    it("still remembers the URL, which is what makes /url a way out", function()
        local ns, env = loggedIn()
        ns.db.chat.rewrite = false

        helpers.say(env, "go to example.com now")
        assertEqual("example.com", ns.History.Get(1))
    end)
end)

describe("shortening", function()
    it("shows only the host for a long link", function()
        local ns, env = loggedIn()
        ns.db.chat.shorten = true

        local long = "https://example.com/a/very/long/path/that/goes/on/and/on"
        local shown = helpers.say(env, "see " .. long)

        assertMatch("%[example%.com%]", shown, "the host is what is shown")
    end)

    it("still carries the whole URL in the link", function()
        local ns, env = loggedIn()
        ns.db.chat.shorten = true

        local long = "https://example.com/a/very/long/path/that/goes/on/and/on"
        local shown = helpers.say(env, "see " .. long)

        assertEqual("urlcopy:" .. long, helpers.linkIn(shown), "nothing is lost")
    end)

    it("leaves a short link in full", function()
        local ns, env = loggedIn()
        ns.db.chat.shorten = true

        local shown = helpers.say(env, "see example.com/a")
        assertMatch("%[example%.com/a%]", shown)
    end)
end)

describe("installing", function()
    it("registers its filters once, however often it is called", function()
        local ns, env = loggedIn()
        ns.Chat.Install()
        ns.Chat.Install()

        assertEqual(1, #env.__filters["CHAT_MSG_SAY"], "one filter, not three")
    end)

    it("records a URL exactly once per message", function()
        local ns, env = loggedIn()
        helpers.say(env, "example.com and example.com again")

        assertEqual(1, #ns.History.All(), "the same URL twice is still one entry")
    end)
end)
