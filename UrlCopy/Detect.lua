local addonName, ns = ...

-- Finding URLs in a line of chat. Nothing here touches the game: it is string
-- matching, which is the half of this addon that is either right or quietly
-- wrong, so it lives where a test can reach it without building a frame.

local Detect = {}
ns.Detect = Detect

local SCHEMES = { http = true, https = true, ftp = true }

-- Top-level domains the bare-domain rule accepts. Deliberately absent, though
-- all are real: no, it, is, me, at, in, be, by, to, so, us, am, as, do, re.
-- Each collides with ordinary English or Swedish -- "wait.no", "call.me",
-- "look.at" -- and turning a sentence into a link is a worse failure than
-- missing a domain. Written properly, with a scheme or www., they still work.
-- ly and gl are in despite the same risk, because bit.ly and goo.gl are
-- common enough in practice to earn it.
local TLDS = {}
for tld in ([[
    com net org edu gov mil info biz io gg tv dev app co ly gl xyz
    online site shop live news wiki
    se nu dk fi uk de fr nl pl eu ca au ru br jp cz es pt ch
]]):gmatch("%a+") do
    TLDS[tld] = true
end

-- What may follow the host. Parentheses and square brackets are left out: they
-- are legal in a URL but in chat they wrap a link far more often than they
-- appear inside one, and "(see example.com/a)" losing its bracket to the link
-- is the more common failure by a wide margin.
--
-- The high-byte range is in for the opposite reason: excluding it truncated
-- every non-ASCII path (a Swedish "läs-mer") at the first such byte, handing
-- back a link that looks confident and is not the one posted -- a worse
-- failure than any this scanner is otherwise built to avoid.
--
-- The pipe is in none of these classes, and that is what guarantees a link we
-- build can never contain one: a pipe ends a match instead of being swallowed.
local PATH = "[%w%-%._~%%:/%?#@!%$&%*%+,;=\128-\255]"

-- Punctuation that belongs to the sentence rather than to the URL.
local TRAILING = "[%.,;:!%?%)%]'\"]+$"

--- Regions no match may begin inside: existing hyperlinks, and the colour and
-- texture escapes. An item or achievement link can hold URL-shaped text, and
-- matching inside one produces a nested link that corrupts chat's parsing.
local function skipRegions(message)
    local regions = {}

    local patterns = { "|H.-|h.-|h", "|T.-|t", "|c%x%x%x%x%x%x%x%x", "|r" }
    for _, pattern in ipairs(patterns) do
        local init = 1
        while true do
            local from, to = message:find(pattern, init)
            if not from then
                break
            end
            regions[#regions + 1] = { from = from, to = to }
            init = to + 1
        end
    end

    -- WoW's 255-byte chat limit routinely truncates a long item link, leaving
    -- an |H or |T with no closing |h/|t. That escape is still open for the
    -- rest of the message, so it must block matches to the end rather than
    -- read as plain text the scanner is free to search inside.
    for _, opener in ipairs({ "|H", "|T" }) do
        local from = message:find(opener, 1, true)
        while from do
            local covered = false
            for _, region in ipairs(regions) do
                if from >= region.from and from <= region.to then
                    covered = true
                    break
                end
            end

            if not covered then
                regions[#regions + 1] = { from = from, to = #message }
                break
            end

            from = message:find(opener, from + 1, true)
        end
    end

    return regions
end

local function insideSkipped(regions, index)
    for _, region in ipairs(regions) do
        if index >= region.from and index <= region.to then
            return true
        end
    end
    return false
end

local function endsRegion(regions, index)
    for _, region in ipairs(regions) do
        if region.to == index then
            return true
        end
    end
    return false
end

--- A URL may not begin in the middle of a word, a path or an email address.
-- A position straight after an escape counts as a clean start: the "f" ending
-- |cffff0000 is not a word, and a URL coloured by another addon starts there.
local function startsCleanly(message, index, regions)
    if index == 1 or endsRegion(regions, index - 1) then
        return true
    end

    local previous = message:sub(index - 1, index - 1)
    -- A pipe would otherwise read as a clean boundary, but an escape this
    -- skip list does not model -- a malformed colour code, an atlas or BNet
    -- escape -- still starts with one, and its leftover characters must not
    -- glue onto the domain that follows it.
    return previous:match("[%w%-%._/@|]") == nil
end

--- Consume a host from `index`: word characters and hyphens, joined by dots.
-- Returns the host and the position just past it, or nil.
local function consumeHost(message, index)
    local host = message:match("^[%w%-]+[%w%-%.]*", index)
    if not host then
        return nil
    end

    -- A trailing dot belongs to the sentence, not to the host.
    host = host:gsub("%.+$", "")
    if host == "" then
        return nil
    end

    return host, index + #host
end

--- Consume an optional ":1234" and then an optional path, from `index`.
-- Returns the position just past the end of the URL.
local function consumeTail(message, index)
    local _, portEnd = message:find("^:%d+", index)
    if portEnd then
        index = portEnd + 1
    end

    local _, pathEnd = message:find("^[/%?#]" .. PATH .. "*", index)
    if pathEnd then
        index = pathEnd + 1
    end

    return index
end

local function octetsInRange(...)
    for index = 1, select("#", ...) do
        local octet = select(index, ...)
        if #octet > 3 or tonumber(octet) > 255 then
            return false
        end
    end
    return true
end

--- Try to match a URL beginning exactly at `index`. Returns the text, or nil.
local function matchAt(message, index)
    local scheme, afterScheme = message:match("^(%a[%w%+%-%.]*)://()", index)
    if scheme then
        if not SCHEMES[scheme:lower()] then
            return nil
        end

        -- An optional "user:pass@" before the host. Skipped whole rather than
        -- left for consumeHost to hit: consumeHost stops at the "@", which
        -- used to return early with "host" set to the userinfo and the real
        -- host dropped -- a link truncated to "https://user" is worse than no
        -- link at all. Absent, there is no bare "@" here for this to match,
        -- so afterScheme is untouched and consumeHost runs on the host as
        -- normal.
        local afterUserinfo = message:match("^[%w%-%._~%%!%$&%*%+,;=:]*@()", afterScheme)
        if afterUserinfo then
            afterScheme = afterUserinfo
        end

        local host, afterHost = consumeHost(message, afterScheme)
        if not host then
            return nil
        end

        return message:sub(index, consumeTail(message, afterHost) - 1)
    end

    if message:find("^www%.", index) then
        local host, afterHost = consumeHost(message, index)
        -- "www." on its own is not a host; there must be something after it.
        if not host or not host:find("^www%.[%w%-]") then
            return nil
        end

        return message:sub(index, consumeTail(message, afterHost) - 1)
    end

    local a, b, c, d, afterQuad = message:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)()", index)
    if a then
        -- A bare dotted quad is a patch or addon version far more often than
        -- it is a server, so this rule asks for a port or a path as proof.
        local addressed = message:find("^:%d", afterQuad) or message:find("^/", afterQuad)
        if addressed and octetsInRange(a, b, c, d) then
            return message:sub(index, consumeTail(message, afterQuad) - 1)
        end

        return nil
    end

    local host, afterHost = consumeHost(message, index)
    if host then
        local tld = host:match("%.(%a+)$")
        if tld and TLDS[tld:lower()] then
            return message:sub(index, consumeTail(message, afterHost) - 1)
        end
    end

    return nil
end

--- Every URL in a message, in order, as { text, from, to } spans.
function Detect.Find(message)
    local found = {}
    if type(message) ~= "string" or message == "" then
        return found
    end

    local skips = skipRegions(message)
    local index = 1
    local length = #message

    while index <= length do
        local url
        if not insideSkipped(skips, index) and startsCleanly(message, index, skips) then
            url = matchAt(message, index)
            if url then
                url = url:gsub(TRAILING, "")
            end
        end

        if url and url ~= "" then
            found[#found + 1] = { text = url, from = index, to = index + #url - 1 }
            index = index + #url
        else
            index = index + 1
        end
    end

    return found
end

--- The host on its own, for a link too long to sit comfortably in chat.
-- No brackets: the caller supplies those, so a shortened link and a full one
-- are bracketed the same way.
function Detect.Shorten(url)
    local host = url:match("^%a[%w%+%-%.]*://([^/%?#]+)") or url:match("^([^/%?#]+)")
    return ((host or url):gsub("^www%.", ""))
end
