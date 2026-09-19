local helpers = require("helpers")

local ns = helpers.loadAddon({ "UrlCopy.lua", "Detect.lua" })
local Detect = ns.Detect

--- The URLs found in a message, as a plain list.
local function found(message)
    local urls = {}
    for index, span in ipairs(Detect.Find(message)) do
        urls[index] = span.text
    end
    return urls
end

--- The single URL a message is expected to contain.
local function one(message)
    local urls = found(message)
    assertEqual(1, #urls, string.format("one URL in [%s], got %d", message, #urls))
    return urls[1]
end

local function none(message)
    assertEqual(0, #found(message), string.format("nothing in [%s]", message))
end

describe("the scheme rule", function()
    it("finds an http URL", function()
        assertEqual("http://example.com", one("go to http://example.com now"))
    end)

    it("finds an https URL with a path and a query", function()
        assertEqual(
            "https://example.com/a/b?c=d&e=f",
            one("see https://example.com/a/b?c=d&e=f")
        )
    end)

    it("finds an ftp URL", function()
        assertEqual("ftp://files.example.com/pub", one("ftp://files.example.com/pub"))
    end)

    it("takes a port", function()
        assertEqual("http://example.com:8080/x", one("http://example.com:8080/x"))
    end)

    it("takes a fragment", function()
        assertEqual("https://example.com/page#part", one("https://example.com/page#part"))
    end)

    it("leaves a scheme it does not know alone", function()
        none("mailto://someone.example")
    end)

    it("is found at the very start of a line", function()
        assertEqual("http://example.com", one("http://example.com is the place"))
    end)

    it("is found at the very end of a line", function()
        assertEqual("http://example.com", one("the place is http://example.com"))
    end)
end)

describe("the www rule", function()
    it("finds a www host with no scheme", function()
        assertEqual("www.example.com", one("try www.example.com"))
    end)

    it("finds a www host with a path", function()
        assertEqual("www.example.co.uk/a/b", one("try www.example.co.uk/a/b"))
    end)

    it("does not care whether the TLD is on the allowlist", function()
        assertEqual("www.example.no", one("try www.example.no"))
    end)
end)

describe("the IPv4 rule", function()
    it("finds an address with a port", function()
        assertEqual("62.109.4.12:3724", one("connect to 62.109.4.12:3724"))
    end)

    it("finds an address with a path", function()
        assertEqual("62.109.4.12/status", one("see 62.109.4.12/status"))
    end)

    it("leaves a bare dotted quad alone, because it is usually a version", function()
        -- "1.14.4.2" is a patch number far more often than it is a server.
        none("we are on patch 1.14.4.2 now")
    end)

    it("leaves an out-of-range quad alone", function()
        none("999.1.1.1:80")
    end)
end)

describe("the bare domain rule", function()
    it("finds a domain on the allowlist", function()
        assertEqual("example.com", one("go to example.com"))
    end)

    it("finds a domain with a path", function()
        assertEqual("discord.gg/abcdef", one("join discord.gg/abcdef"))
    end)

    it("finds a shortener", function()
        assertEqual("bit.ly/xyz", one("bit.ly/xyz"))
    end)

    it("finds a Swedish domain", function()
        assertEqual("esatto.se", one("we are esatto.se"))
    end)

    it("leaves a TLD that collides with ordinary words alone", function()
        -- Every one of these is a real TLD. Linking a sentence is worse than
        -- missing a domain, so the allowlist leaves them out.
        none("wait.no")
        none("call.me")
        none("look.at")
        none("do it.it")
        none("that.is")
        none("get.in")
    end)

    it("leaves a file name alone", function()
        none("open Interface.toc")
    end)

    it("leaves an email address alone", function()
        none("mail me at someone@example.com")
    end)

    it("leaves a mid-word match alone", function()
        none("see-example.com-ish")
    end)
end)

describe("trailing punctuation", function()
    it("drops a full stop", function()
        assertEqual("example.com", one("see example.com."))
    end)

    it("drops a comma", function()
        assertEqual("http://example.com", one("http://example.com, then leave"))
    end)

    it("drops a closing bracket", function()
        assertEqual("example.com/a", one("(see example.com/a)"))
    end)

    it("drops a question mark that ends the sentence", function()
        assertEqual("example.com", one("have you seen example.com?"))
    end)

    it("keeps a trailing slash", function()
        assertEqual("http://example.com/", one("http://example.com/ is fine"))
    end)
end)

describe("several URLs in one line", function()
    it("finds them all, in order", function()
        local urls = found("first example.com then http://other.org/x last")
        assertEqual(2, #urls)
        assertEqual("example.com", urls[1])
        assertEqual("http://other.org/x", urls[2])
    end)

    it("reports offsets that address the original text", function()
        local message = "go to example.com now"
        local span = Detect.Find(message)[1]
        assertEqual("example.com", message:sub(span.from, span.to))
    end)

    it("never overlaps two spans", function()
        local spans = Detect.Find("a.com b.com c.com")
        assertEqual(3, #spans)
        assertTrue(spans[1].to < spans[2].from)
        assertTrue(spans[2].to < spans[3].from)
    end)
end)

describe("regions the scanner must not touch", function()
    it("ignores a URL inside an existing hyperlink", function()
        -- An item called something URL-shaped must not gain a nested link.
        none("|cffffffff|Hitem:6948:0:0:0|h[Hearthstone.net]|h|r")
    end)

    it("still finds a URL after a hyperlink has closed", function()
        local message = "|Hitem:6948:0:0:0|h[Hearthstone]|h and example.com"
        assertEqual("example.com", one(message))
    end)

    it("finds a URL wrapped in a colour escape", function()
        assertEqual("http://example.com", one("|cffff0000http://example.com|r"))
    end)

    it("ignores a texture escape", function()
        none("|TInterface\\Icons\\INV_Misc_Note_01:14|t")
    end)
end)

describe("pipes", function()
    it("ends a match rather than being swallowed", function()
        -- A pipe inside a link would let a crafted message close our link
        -- early and write its own markup into the player's chat frame.
        local url = one("http://evil.com|cffff0000nope|r")
        assertEqual("http://evil.com", url)
        assertNil(url:find("|", 1, true), "no pipe survives into a URL")
    end)
end)

describe("Shorten", function()
    it("returns the host of a scheme URL", function()
        assertEqual("example.com", Detect.Shorten("https://example.com/a/b?c=d"))
    end)

    it("strips a www prefix", function()
        assertEqual("example.com", Detect.Shorten("www.example.com/a"))
    end)

    it("keeps a port, which is part of the address", function()
        assertEqual("example.com:8080", Detect.Shorten("http://example.com:8080/a"))
    end)

    it("returns a bare host unchanged", function()
        assertEqual("example.com", Detect.Shorten("example.com"))
    end)

    it("adds no brackets, because the caller supplies those", function()
        assertNil(Detect.Shorten("https://example.com/a"):find("[", 1, true))
    end)
end)

describe("odd input", function()
    it("survives an empty message", function()
        assertEqual(0, #Detect.Find(""))
    end)

    it("survives a nil message", function()
        assertEqual(0, #Detect.Find(nil))
    end)

    it("survives a message that is only punctuation", function()
        assertEqual(0, #Detect.Find("... ,,, !!!"))
    end)
end)
